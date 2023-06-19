import gleam/bit_string
import gleam/io
import gleam/erlang
import gleam/erlang/file
import gleam/erlang/os
import gleam/result
import gleam/list
import gleam/string
import mote/toml
import shellout
import glint
import glint/flag

pub fn main() {
  let config = get_project_config()

  let target_default = case os.family() {
    os.WindowsNt -> "windows-x64"
    os.Darwin -> "macos-x64"
    os.Linux -> "linux-x64"
    _ -> "linux-x64"
  }

  glint.new()
  |> glint.add_command(
    at: [],
    do: pack(_, config),
    with: [
      flag.string("runtime", "", "Decide which runtime to pack with"),
      flag.string("target", target_default, "Decide with target to pack for"),
    ],
    described: "Packs your project into an executable",
  )
  |> glint.run(erlang.start_arguments())
}

fn get_project_config() -> toml.Section {
  let assert Ok(data) = file.read("gleam.toml")
  let assert Ok(data) = toml.parse(data)
  data
}

fn pack(input: glint.CommandInput, config: toml.Section) {
  io.println("mote packaging starting...")

  let assert Ok(flag.S(runtime)) = flag.get(input.flags, "runtime")

  case runtime {
    "" -> {
      io.println_error("you must set a runtime to pack with")
      panic
    }
    _ -> Nil
  }

  let assert Ok(_) =
    shellout.command(
      run: "gleam",
      with: ["export", "erlang-shipment"],
      in: ".",
      opt: [],
    )

  let assert Ok(project_name) = toml.get_string(config, ["name"])

  let shipment_folder = "build/erlang-shipment"
  let pkg_dir = "build/mote_pkg"

  let _ = file.recursive_delete(pkg_dir)
  let assert Ok(_) = copy_rec(shipment_folder, pkg_dir)
  let assert Ok(_) = file.delete(pkg_dir <> "/entrypoint.sh")

  let runtimes = case os.get_env("GLEAM_MOTE_RUNTIMES") {
    Ok(r) -> r
    _ -> {
      io.println_error(
        "please set the `GLEAM_MOTE_RUNTIMES` environment variable to a directory containing your erlang runtimes to pack",
      )
      panic
    }
  }

  let runtime_src = runtimes <> "/" <> runtime
  case file.is_directory(runtime_src) {
    Ok(True) -> Nil
    _ -> {
      io.println_error(runtime_src <> " is not a valid runtime directory")
      panic
    }
  }

  let assert Ok(modules) = file.list_directory(pkg_dir)

  let runtime = pkg_dir <> "/minimal_erl"
  let assert Ok(Nil) = copy_rec(runtime_src, runtime)

  let assert Ok(runtime_dir) = file.list_directory(runtime)

  let assert Ok(erts_dir) =
    runtime_dir
    |> list.find(string.starts_with(_, "erts"))
  let erts_dir = runtime <> "/" <> erts_dir

  runtime_dir
  |> list.map(fn(item) {
    case
      item
      |> string.ends_with(".exe") || item
      |> string.ends_with(".ini") || item
      |> string.ends_with(".md") || item
      |> string.ends_with(".template")
    {
      True ->
        file.delete(runtime <> "/" <> item)
        |> result.unwrap(Nil)
      False -> Nil
    }
  })

  let _ = file.recursive_delete(runtime <> "/doc")
  let _ = file.recursive_delete(runtime <> "/releases")
  let _ = file.recursive_delete(runtime <> "/usr")

  ["doc", "include", "man", "src", "info"]
  |> list.map(fn(dir) {
    let _ = file.recursive_delete(erts_dir <> "/" <> dir)
  })

  let module_include =
    modules
    |> list.map(fn(mod) {
      "\t\tunicode:characters_to_list([RootPath, \"" <> mod <> "/ebin\"])"
    })
    |> string.join(",\n")

  let assert Ok(Nil) =
    file.write(
      "\n-module(launch).\n" <> "-mode(compile).\n" <> "main(_) ->\n" <> "\tErlPath = code:root_dir()," <> "\tTrimLength = string:length(\"minimal_erl\")," <> "\tRootPath = string:reverse(string:slice(string:reverse(ErlPath), TrimLength))," <> "\tcode:add_paths([\n" <> module_include <> "\n\t]),\n\t" <> project_name <> ":main().",
      runtime <> "/bin/launch.escript",
    )

  let assert Ok(_) =
    copy(runtime <> "/bin/escript.exe", runtime <> "/bin/launch.exe")

  let _ = kill_inis(runtime, erts_dir)

  apply_whitelists(runtime, erts_dir, config)

  clean_libs(runtime)

  let assert Ok(flag.S(target)) = flag.get(input.flags, "target")
  case target {
    "windows-x64" | "macos-x64" | "linux-x64" -> Nil
    _ -> {
      io.println_error("invalid target `" <> target <> "`")
      panic
    }
  }
  launch_warp(project_name, pkg_dir, target)

  io.println("mote packaging completed.")
}

fn launch_warp(project_name: String, pkg_dir: String, target: String) {
  case os.family() {
    os.WindowsNt ->
      case
        shellout.command(
          run: "warp-packer",
          with: [
            "-a",
            target,
            "-i",
            ".",
            "-e",
            "minimal_erl\\bin\\launch.exe",
            "-o",
            project_name <> ".exe",
          ],
          in: pkg_dir,
          opt: [],
        )
      {
        Ok(_) -> Nil
        Error(#(_, err)) -> {
          io.println_error(
            "failed to launch warp packer with error `" <> err <> "`. Have you installed warp and added it to your path?",
          )
          panic
        }
      }
    os.Darwin ->
      case
        shellout.command(
          run: "warp-packer",
          with: [
            "-a",
            target,
            "-i",
            ".",
            "-e",
            "minimal_erl/bin/launch.exe",
            "-o",
            project_name <> ".exe",
          ],
          in: pkg_dir,
          opt: [],
        )
      {
        Ok(_) -> Nil
        Error(#(_, err)) -> {
          io.println_error(
            "failed to launch warp packer with error `" <> err <> "`. Have you installed warp and added it to your path?",
          )
          panic
        }
      }
    _ ->
      case
        shellout.command(
          run: "warp-packer",
          with: [
            "-a",
            target,
            "-i",
            ".",
            "-e",
            "minimal_erl/bin/launch.exe",
            "-o",
            project_name <> ".exe",
          ],
          in: pkg_dir,
          opt: [],
        )
      {
        Ok(_) -> Nil
        Error(#(_, err)) -> {
          io.println_error(
            "failed to launch warp packer with error `" <> err <> "`. Have you installed warp and added it to your path?",
          )
          panic
        }
      }
  }
}

external fn copy(src: String, dst: String) -> Result(Int, file.Reason) =
  "file" "copy"

fn copy_rec(source: String, dest: String) -> Result(Nil, file.Reason) {
  case file.is_directory(source) {
    Ok(True) -> {
      let source = source <> "/"
      let _ = file.make_directory(dest)
      let dest = dest <> "/"
      use files <- result.try({ file.list_directory(source) })
      result.all({
        files
        |> list.map(fn(item) { copy_rec(source <> item, dest <> item) })
      })
      |> result.map(fn(_) { Nil })
    }
    Ok(False) -> {
      copy(source, dest)
      |> result.map(fn(_) { Nil })
    }
    _ -> Ok(Nil)
  }
}

fn apply_whitelists(runtime: String, erts_dir: String, config: toml.Section) {
  let bin_dir = runtime <> "/bin/"
  case toml.get(config, ["mote", "bin_whitelist"]) {
    Ok(toml.ValueList(files)) -> {
      let files =
        files
        |> list.filter_map(fn(item) {
          case item {
            toml.Binary(bitstring) -> bit_string.to_string(bitstring)
            _ -> Error(Nil)
          }
        })

      file.list_directory(bin_dir)
      |> result.unwrap([])
      |> list.map(fn(file) {
        case
          files
          |> list.contains(file)
        {
          True -> Nil
          False -> {
            let assert Ok(Nil) = file.delete(bin_dir <> file)
            Nil
          }
        }
      })

      Nil
    }
    _ -> io.println("no bin whitelist found, skipping")
  }

  let erts_bin_dir = erts_dir <> "/bin/"
  case toml.get(config, ["mote", "erts_bin_whitelist"]) {
    Ok(toml.ValueList(files)) -> {
      let files =
        files
        |> list.filter_map(fn(item) {
          case item {
            toml.Binary(bitstring) -> bit_string.to_string(bitstring)
            _ -> Error(Nil)
          }
        })

      file.list_directory(erts_bin_dir)
      |> result.unwrap([])
      |> list.map(fn(file) {
        case
          files
          |> list.contains(file)
        {
          True -> Nil
          False -> {
            let assert Ok(Nil) = file.delete(erts_bin_dir <> file)
            Nil
          }
        }
      })

      Nil
    }
    _ -> io.println("no erts bin whitelist found, skipping")
  }

  let lib_dir = runtime <> "/lib/"
  case toml.get(config, ["mote", "lib_whitelist"]) {
    Ok(toml.ValueList(files)) -> {
      let files =
        files
        |> list.filter_map(fn(item) {
          case item {
            toml.Binary(bitstring) -> bit_string.to_string(bitstring)
            _ -> Error(Nil)
          }
        })

      file.list_directory(lib_dir)
      |> result.unwrap([])
      |> list.map(fn(file) {
        case
          files
          |> list.any(string.starts_with(file, _))
        {
          True -> Nil
          False -> {
            let assert Ok(Nil) = file.recursive_delete(lib_dir <> file)
            Nil
          }
        }
      })

      Nil
    }
    _ -> io.println("no lib whitelist found, skipping")
  }
}

fn clean_libs(runtime: String) {
  let lib_dir = runtime <> "/lib"

  let blacklist = ["doc", "include", "src", "examples"]
  walk_directory(
    lib_dir,
    fn(file, path) {
      case list.contains(blacklist, file) {
        True -> {
          let assert Ok(Nil) = file.recursive_delete(path)
          False
        }
        False -> True
      }
    },
  )
}

fn walk_directory(dir: String, for_each: fn(String, String) -> Bool) {
  dir
  |> file.list_directory
  |> result.unwrap([])
  |> list.map(fn(file) {
    let filepath = dir <> "/" <> file
    case file.is_directory(filepath) {
      Ok(True) -> {
        case for_each(file, filepath) {
          True -> walk_directory(filepath, for_each)
          False -> Nil
        }
      }
      Ok(False) -> {
        for_each(file, filepath)
        Nil
      }
      _ -> {
        io.println_error(
          "failed to walk file " <> file <> " at path " <> dir <> "/" <> file,
        )
        panic
      }
    }
  })
  Nil
}

fn kill_inis(runtime: String, erts_dir: String) {
  let _ = file.delete(runtime <> "/bin/erl.ini")
  let _ = file.delete(erts_dir <> "/bin/erl.ini")
}
