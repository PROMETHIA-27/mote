# mote

A gleam executable bundler.

# Installation:
- Download a release of `mote`, and make it accessible for your project (either in the project directory, on your path, etc)
- Install [`warp-packer`](https://github.com/dgiagio/warp/tree/master) and make it accessible as well (recommended to put it on the path)
- Create a folder somewhere containing at least one erlang runtime, and add it to the environment variable `GLEAM_MOTE_RUNTIMES`
  - Example runtime folder:
```
erlang_runtimes
- windows_x64
  - bin
  - erts-14.0.1
  - ...
- linux_x64
  - bin
  - erts-14.0.1
  - ...
```
  - Example envvar:
      - `SET GLEAM_MOTE_RUNTIMES=C:\users\madelline\erlang_runtimes`
   
# Usage:
In your project's root directory, run `mote --runtime <RUNTIME>` to pack your project with the given runtime.
Add the `--target` flag (options `windows-x64`, `macos-x64`, `linux-x64`) to pack for a target other than your current environment.

In your `gleam.toml` file, you can add extra options to strip out unnecessary components (this can net you a 90+% reduction in executable size! Primarily via the lib whitelist)
This example setup will reduce your setup to more or less the minimal possible components:
```toml
[mote]
bin_whitelist = [
    "erl.exe",
    "launch.escript",
    "launch.exe",
    "no_dot_erlang.boot",
]
erts_bin_whitelist = [
    "beam.smp.dll",
    "erlexec.dll",
]
lib_whitelist = [
    "compiler",
    "kernel",
    "stdlib",
]
```

This does remove many components of the erlang runtime that might be necessary depending on what you were doing. For example, the lib whitelist is stripping out libraries such as `xmerl` that are used for xml handling.
The erts bin whitelist is removing components such as `heart` which are presumably necessary for the heartbeat functionality of the erlang runtime.
However, for "normal" apps, many of these components should be unnecessary.
