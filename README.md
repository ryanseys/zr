# zr

**A Ruby compiler, written in Ruby.** zr compiles Ruby programs to
native binaries and WebAssembly modules. A compiled program gives
exactly the output that ruby 4.0.6 gives. When zr cannot promise this
for a program, it refuses to compile it, and gives the line.

```console
$ cat hello.rb
puts "Hello, #{ARGV.first || "world"}!"

$ zr build hello.rb -o hello
$ ./hello Ruby
Hello, Ruby!
```

The compiler, the runtime, the core library, the parser and the
garbage collector are all Ruby. The repository has no C or
assembler.

## Install

```console
$ gem install zr
```

You need:

- ruby 4.0.6 exactly. zr runs on this version and checks its output
  against it;
- [wasmtime](https://wasmtime.dev), to run WebAssembly modules;
- OpenSSL 3 (`brew install openssl@3`), only for a macOS program that
  requires `openssl`.

The install compiles nothing. zr links a macOS binary itself, so it
needs no C compiler and no linker.

## Use

```console
$ zr run app.rb arg1 arg2                    # compile, run with the arguments, then delete the build
$ zr build app.rb -o app                     # a native binary
$ zr build app.rb -o app.wasm --emit wasm    # a WASI module
$ zr build app.rb -o app.o --emit obj        # an object file
$ zr build app.rb -o app --target aarch64-linux-musl
$ zr targets                                 # what this host can build
$ zr help build                              # the options of a command
```

A binary contains your program, Ruby's core library and the runtime.
It needs no ruby and no gems to run. `zr` exits with status 2 for a
usage error and 3 when it refuses a program; see
[The `zr` command](docs/reference/cli.md).

New to zr? Start with the tutorial
[Compile your first program](docs/tutorials/compile-your-first-program.md).

## What it builds

| Target | Output | Built on |
|---|---|---|
| `aarch64-apple-darwin` | native binary | any host |
| `aarch64-linux-musl` | static binary | aarch64 Linux, or a host with a musl cross toolchain |
| `wasm32-wasi` | WASI module | any host |

Some features depend on the target. For example, a WASI module has no
fibers, threads or ractors. See [Targets](docs/reference/targets.md).

## How it works

```
app.rb ─► prism ─► HIR ─► IR ─┬─► aarch64 machine code ─► binary
                              └─► WebAssembly ─► WASI module
```

- **prism** parses the program. zr uses a Ruby port of the parser that
  ruby uses.
- **The HIR** is the program as a plain tree: desugared, with names
  resolved. zr refuses a form that it does not support here.
- **The IR** is one SSA form that every backend reads.
- **The runtime** is compiled into every program: a kernel in the
  machine dialect (Ruby syntax, machine semantics), and the core
  library in ordinary Ruby.

ruby 4.0.6 is the only source of expected outputs. zr must match
ruby's output byte for byte. See
[Architecture](docs/explanation/architecture.md) and
[The contract](docs/explanation/the-contract.md).

## Contribute

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup                        # install the gems and build the runtime (a few minutes)
$ bin/test test/spec/core/string   # the tests in one directory
$ bin/test                         # all the tests: unit, spec, e2e
```

`bin/test` builds the runtime again when a change under `lib/` or
`runtime/` makes it out of date. Read [CONTRIBUTING.md](CONTRIBUTING.md)
before you open a pull request, and the tutorial
[Add your first spec](docs/tutorials/add-your-first-spec.md).

## Development

```console
$ rake lint       # RuboCop's Lint cops
$ rake build      # build the runtime for this host
$ bin/console     # IRB with zr loaded
$ rake -T         # every rake task
$ ruby tool/zr-dev.rb help   # every maintainer tool
```

See [How to run the tests](docs/how-to/run-the-tests.md) and
[Tools](docs/reference/tools.md). All the
documentation is in [`docs/`](docs/README.md).

## Release

1. Change the version in `lib/zr/version.rb`.
2. In `CHANGELOG.md`, change `[Unreleased]` to the new version and the
   date.
3. Commit, then tag the commit `vX.Y.Z` and push the tag.

The release workflow (`.github/workflows/release.yml`) starts on the
tag. It runs the unit tests (`bin/test test/unit`), then publishes the
gem to rubygems.org with `rake release`, and to gem.coop.

## License

zr is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses. `THIRD_PARTY_NOTICES.md` lists each
one.
