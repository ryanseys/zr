# The Ruby API

`require "zr"` gives `Zr.build`: the build of `zr build`, from Ruby. It
writes the same bytes as `zr build` does, and raises an error where
`zr build` exits with a status.

```ruby
require "zr"

result = Zr.build("app.rb", out: "app")
result.path      # => "/abs/app"
result.target    # => "aarch64-apple-darwin"
result.warnings  # => ["zr: warning: ..."]
```

## `Zr.build`

```ruby
Zr.build(file = nil, source: nil, out:, target: nil, emit: :binary,
         settings: {}, diagnostics: $stderr) -> Zr::Result
```

| Argument | Value |
|---|---|
| `file` | The path of the program. With `source:`, the name that the program has (`__FILE__`); default `"-"`. |
| `source:` | The program's text, in place of the file's. |
| `out:` | The path to write. zr writes a draft beside it and renames it into place, so a build that stops leaves the old file. |
| `target:` | A triple of [Targets](targets.md). Default: this host's target, else `aarch64-apple-darwin`. |
| `emit:` | `:binary` (default), `:obj` or `:wasm`. |
| `settings:` | The settings of `zr help`, by the name of their flag with `_` for `-`: `jobs: 2`, `linker: "cc"`, `cache_dir: "/tmp/zr"`, `verify: true`, `native_ext: ["msgpack"]`. `run_cache`, `tune` and `backtrace` apply to the command only. |
| `diagnostics:` | Where each line that the build prints goes: an IO, an object that takes `call(line)`, or nil for none. |

`Zr::Result` has `path`, `target` (the triple), `emit`, `warnings` (the
lines that start `zr: warning:`) and `gems` (the gems that the program
uses).

## Errors

Each error that the caller can fix includes `Zr::Error`, so
`rescue Zr::Error` catches them all. Any other error is a defect in zr:
[report it](https://github.com/ryanseys/zr/issues).

| Error | When |
|---|---|
| `Zr::Refused` | zr does not support a form of the program. `file`, `line`, `column` and `form` say which. |
| `Zr::InvalidProgram` | The program does not parse, or ruby's compiler rejects it. `zr build` compiles such a program into one that prints ruby's error; `Zr.build` raises. |
| `Zr::TargetRefused` | This host cannot build for the target, or zr does not run on this ruby or OS. |
| `Zr::Config::Invalid` | A setting has a value that zr cannot use. It is an `ArgumentError` too. |
| `Zr::GemSet::Unresolved` | The program's gems do not resolve. |
| `Zr::Paths::Untrusted` | The cache is not this user's alone (see `SECURITY.md`). |
| `Zr::BuildError` | A backend cannot compile the code, or the link or the write failed. |

## What a build from Ruby does to the process

- **One build at a time.** A build keeps its state in the process
  (`Zr::Session`), as a `zr` process does. `Zr.build` holds
  `Zr::BUILD_LOCK` for the build, so two threads build one after the
  other. A `diagnostics` callback must not call `Zr.build`: it would
  wait for itself.
- **Workers.** A large build forks worker processes. In a program with
  threads, give `settings: { jobs: 1 }` to build in the process alone.
  A worker writes its lines to the process's own stderr.
- **Environment.** zr reads no `ZR_*` variable for the build: the
  settings come from `settings:`. It still reads `PATH`, `HOME`,
  `XDG_CACHE_HOME`, `TMPDIR`, `CC`, `BUNDLE_GEMFILE` and the gem
  variables, as `zr build` does. While the build runs, `$stderr` is
  the diagnostics.
- **No restart.** `zr build` starts ruby again with larger collector
  limits and YJIT; `Zr.build` does not.

## Stability

Before 1.0, a minor release can change this API; the changelog says
so. Only `Zr.build`, `Zr::Result`, `Zr::Error` and the error classes
above are the API. Every other constant under `Zr::` is internal.
