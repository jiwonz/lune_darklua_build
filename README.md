# lune_darklua_build

A [darklua](https://darklua.com/) build script for [Lune](https://lune-org.github.io/docs).
Also comes as a library for usage within Lune scripts.

## Install

### With pesde

```sh
pesde add pesde/darklua --dev -t lune # May be specified as a peer dependecy
pesde add ewdev/darklua_build --dev -t lune
pesde install
```

## Usage (script)

pesde.toml:

```toml
[dev_dependencies]
darklua = { name = "pesde/darklua", version = "^0.16.0" }
darklua_build = { name = "ewdev/darklua_build", version = "^0.1.0" }

[scripts]
build = ".pesde/darklua_build/darklua_build.luau"
```

```sh
pesde run build # Builds from src, into out
```

Script options:

```sh
--input / -i [Path]
# Path to what to process (defaults to "src").

--output / -o [Path]
# Path to the output folder (defaults to "out").

--config / -c [Path]
# Path to a build config file. If left empty (or invalid): attempts to find any .darklua.build.json / .darklua.build.toml / .darklua.build.yaml

--silent / -s
# If provided, silences all non error messages.

--watch / -w
# If provided, listens to any changes to any input / build file, and automatically re-runs the build script.
```

.darklua.build.toml (.json / .yaml also supported)

```toml
input = "src" # Path to what to process (defaults to "src").
output = "out" # Path to the output folder (defaults to "out").

[options] # An optional dictionary containing a set of build options.
cwd = "." # Sets the relative path of all other paths, including input and output.
include = [ # List of globs for files to include while building (also copied over to the output)
    "roblox_packages/**/*", ".darklua.json", "*.project.json", "sourcemap.json"
]
ignore = [ "*.d." ] # List of globs for files to ignore (also ignores files for files under the input path)
darklua_config = ".darklua.json" # Custom path to your darklua config file (if left empty: uses default config path)

silent = false # If set to true, silences all non error messages.
watch = false # If set to true, listens to any changes to any input / build file, and automatically re-runs the build script.

temp_dir_keep = false # If true, keeps the temporary build directory that's created after finishing.
temp_dir_location = "." # Path for where to create the temporary build directory (defaults to system temp directory, unless temp_dir_keep is enabled where the current directory is used instead)
```

## Usage (library)

```lua
if not _G.LUA_ENV then
	_G.LUA_ENV = "lune"
end

local darklua_build = require("path/to/package")
darklua_build(
    inputPath, -- Path to what to process.
    outputPath, -- Path to the output folder.
    { -- An optional dictionary containing a set of build options.
        include = { "roblox_packages/**/*", ".darklua.json", "*.project.json", "sourcemap.json" },
        ignore = { "*.d." }

        -- For a list of options, and what they do, refer to the example .darklua.build.toml above.
    }
)
```

## Todo

- [ ] Refactor code.
- [ ] A separate include array, for files that aren't required while building, but should be included in the output (should improve build times).
- [ ] A way to provide scripts to run before and after building (useful for example to generate rojo sourcemaps required while building).
- [ ] Reduce the amount of copying and overwriting files that haven't changed.
