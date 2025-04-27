local luau_path = require("@luau_pkg/luau_path")
local dirs = require("@pkg/dirs")
local pathfs = require("@pkg/pathfs")
local glob = require("@pkg/glob")
local progressbar = require("@pkg/progressbar")
local pesde_exec = require("@pkg/pesde_exec")

local stdio = require("@lune/stdio")
local task = require("@lune/task")

local fs = pathfs.fs
local Path = luau_path.Path

local clr = stdio.color

type AsPath = luau_path.AsPath
type Path = luau_path.Path

export type Options = {
	include: { string }?,
	ignore: { string }?,
	cwd: AsPath?,
	darklua_config: AsPath?,
	temp_dir: AsPath?,
	temp_dir_keep: boolean?,
	silent: boolean?,
	watch: boolean?,
}

local function reconcileFiles(files: { Path }, into: Path, cwd: Path)
	for _, path in ipairs(files) do
		local destPath = into:join(assert(path:stripPrefix(cwd)))

		local parent = destPath:parent()
		if parent then
			fs.writeDir(parent)
		end

		if fs.isFile(path) then
			-- Copy whole files
			fs.copy(path, destPath, true)
		elseif fs.isDir(path) then
			-- But don't copy folder contents
			fs.writeDir(destPath)
		end
	end
end

local function getBuildTime(start: number)
	return `{math.round((os.clock() - start) * 1000 * 10000) / 10000} ms`
end

type Files = { Path }
local function build(input: AsPath, output: AsPath, options: Options?)
	local uoptions = (options or {}) :: Options

	local workingDirPath = Path.from(uoptions.cwd or pathfs.cwd())

	local inputFileGlobs = { Path.from(input):toString() .. "/**/*" }
	local buildFileGlobs = uoptions.include or {}
	local globOptions = {
		cwd = workingDirPath,
		ignore = uoptions.ignore,
	}

	local function doBuild(inputFiles: Files?, buildFiles: Files?): (Files, Files)
		local buildStart = os.clock()

		-- stylua: ignore
		local bar = progressbar.new()
			:withStage("resolve", "Resolving files")
			:withStage("process", "Processing with Darklua")
			:withStage("output", "Copying files to output")

		if not uoptions.silent then
			bar:start()
		end

		local outputPath = workingDirPath:join(output)
		local darkluaConfigPath = if uoptions.darklua_config then workingDirPath:join(uoptions.darklua_config) else nil

		local resolvedInputFiles = inputFiles or glob(inputFileGlobs, globOptions)
		local resolvedBuildFiles = buildFiles or glob(buildFileGlobs, globOptions)

		local buildDir = dirs.createTempDir(
			if uoptions.temp_dir then workingDirPath:join(uoptions.temp_dir) else nil,
			"darklua_build_"
		)

		local function finish(write: boolean?)
			if not uoptions.silent then
				bar:stop()
			end

			if not uoptions.temp_dir_keep then
				buildDir:removeDir()
			end

			if write and not uoptions.silent then
				stdio.write(`{clr("green")}Built in {getBuildTime(buildStart)}{clr("reset")}\n`)
			end

			return resolvedInputFiles, resolvedBuildFiles
		end

		reconcileFiles(resolvedInputFiles, buildDir.path, workingDirPath)
		reconcileFiles(resolvedBuildFiles, buildDir.path, workingDirPath)

		bar:nextStage() -- process

		local processDir = buildDir.path:join(input):toString()
		local configPath = if darkluaConfigPath then darkluaConfigPath:toString() else nil

		if not configPath then
			if fs.isFile(buildDir.path:join(".darklua.json")) then
				configPath = buildDir.path:join(".darklua.json"):toString()
			elseif fs.isFile(buildDir.path:join(".darklua.json5")) then
				configPath = buildDir.path:join(".darklua.json5"):toString()
			end
		end

		local args = {
			"process",
			processDir,
			processDir,
		}

		if configPath then
			table.insert(args, "--config")
			table.insert(args, configPath)
		end

		local result = pesde_exec("darklua", args)
		if result.ok and #result.stderr > 0 then
			result = {
				ok = false,
				code = 1,
				stdout = result.stdout,
				stderr = result.stderr,
			}
		end

		if not result.ok then
			local returnValues = table.pack(finish())

			stdio.write(clr("red") .. string.rep("-", 20) .. clr("reset") .. "\n")
			stdio.write(result.stderr)
			stdio.write(clr("red") .. string.rep("-", 20) .. clr("reset") .. "\n")

			-- if not uoptions.watch then
			-- 	process.exit(result.code) -- lune panic bug
			-- end

			return unpack(returnValues, 1, returnValues.n)
		end

		bar:nextStage() -- output

		local outDir = pathfs.Directory.new(outputPath)
		outDir:writeDir()

		fs.copy(processDir, outDir.path:join(input), true)
		reconcileFiles(resolvedBuildFiles, outDir.path, workingDirPath)

		return finish(true)
	end

	local inputFiles, buildFiles = doBuild()
	if not uoptions.watch then
		return
	end

	-- WATCH THREAD
	task.defer(function()
		local lastModified = {}
		local function refreshModified(filesArray: { Files })
			table.clear(lastModified)
			for _, files in ipairs(filesArray) do
				for _, path in ipairs(files) do
					lastModified[path:toString()] = fs.metadata(path).modifiedAt
				end
			end
		end

		refreshModified({ inputFiles, buildFiles })

		while task.wait(1) do
			local newInputFiles = glob(inputFileGlobs, globOptions)
			local newBuildFiles = glob(buildFileGlobs, globOptions)
			local filesArray = { newInputFiles, newBuildFiles }

			local modified = #inputFiles ~= #newInputFiles or #buildFiles ~= #newBuildFiles
			if not modified then
				for _, files in ipairs(filesArray) do
					for _, path in ipairs(files) do
						local modifiedAt = fs.metadata(path).modifiedAt
						local lastModifiedAt = lastModified[path:toString()]
						if modifiedAt ~= lastModifiedAt then
							modified = true
							break
						end
					end

					if modified then
						break
					end
				end
			end

			-- There's no need to check if any files got deleted, as we check if they length has changed, and if a file has gotten added.
			-- There's no way a file could've been deleted without either modifying the length of the scanned files, or adding a new file to make up for that.

			if modified then
				refreshModified(filesArray)
				inputFiles, buildFiles = doBuild(newInputFiles, newBuildFiles)
			end
		end
	end)
end

return build
