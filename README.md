# zr

**A Ruby compiler, written in Ruby.** zr compiles Ruby programs to
native binaries and WebAssembly modules. A compiled program answers
exactly what ruby 4.0.6 answers. When zr cannot promise that for a
program, it refuses to compile it, and names the line.

```console
$ cat hello.rb
puts "Hello, #{ARGV.first || "world"}!"

$ zr build hello.rb -o hello
$ ./hello Ruby
Hello, Ruby!
```

The compiler, the runtime, the core library, the parser and the garbage
collector are all Ruby. There is no C, Rust or assembler in the
repository.

## Install

```console
$ gem install zr
```

You need:

- ruby 4.0.6 exactly (zr checks its output against this version);
- [wasmtime](https://wasmtime.dev), to run WebAssembly modules;
- OpenSSL 3 (`brew install openssl@3`), only for a macOS program that
  requires `openssl`. The binary opens the library when that `require`
  runs, and raises `LoadError` when the library is absent.

The install compiles nothing. zr links a macOS binary itself, so it
needs no C compiler and no linker.

## Use

```console
$ zr run app.rb                              # compile, run, and clean up
$ zr build app.rb -o app                     # a native binary
$ zr build app.rb -o app.wasm --emit wasm    # a WASI module
$ zr build app.rb -o app --target aarch64-linux-musl
$ zr targets                                 # what this machine can build
```

A binary holds your program, Ruby's core library and the runtime. It
needs no ruby and no gems to run.

New to zr? Start with the tutorial
[Compile your first program](docs/tutorials/compile-your-first-program.md).

## What it builds

| Target | Output | Built on |
|---|---|---|
| `aarch64-apple-darwin` | native binary | an Apple Silicon Mac |
| `aarch64-linux-musl` | static binary | aarch64 Linux, or any host with a musl cross toolchain |
| `wasm32-wasi` | WASI module | any host |

Some features depend on the target. For example, fibers, threads and
ractors are not available in a WASI module. See
[Targets](docs/reference/targets.md).

## How it works

```
app.rb ─► prism ─► HIR ─► IR ─┬─► aarch64 machine code ─► binary
                              └─► WebAssembly ─► WASI module
```

- **prism** parses the program. It is a Ruby port of the parser that
  ruby itself uses.
- **The HIR** is the program as a plain tree: desugared, with names
  resolved. A form zr cannot compile is refused here.
- **The IR** is one SSA form that every backend reads.
- **The runtime** is compiled into every program: a kernel in a typed
  dialect of Ruby, and the core library in ordinary Ruby.

ruby 4.0.6 is the only source of right answers. Every test program
carries ruby's recorded output, and zr must match it byte for byte.

Read more in [Architecture](docs/explanation/architecture.md) and
[The contract](docs/explanation/the-contract.md).

## Contribute

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup                      # install the gems and build the runtime (a few minutes)
$ bin/test test/unit             # zr's own internals
$ bin/test test/spec -n /blocks/ # Ruby specs, checked against ruby 4.0.6
$ bin/test                       # every tier: unit, spec, e2e
```

`bin/test` builds the runtime again when a change under `lib/` or
`rt/` makes it out of date. The runtime and other build products go to
the cache in `tmp/rt/`.

The tutorial [Add your first spec](docs/tutorials/add-your-first-spec.md)
walks through the loop behind most changes. Then see:

- [How to debug a program that diverges](docs/how-to/debug-a-program-that-diverges.md)
- [How to add a method to the core library](docs/how-to/add-a-core-method.md)
- [How to run the checks](docs/how-to/run-the-checks.md)
- [Repository layout](docs/reference/repository-layout.md)

## Documentation

All the documentation is in [`docs/`](docs/README.md): tutorials,
how-to guides, reference and explanation.

## License

zr is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses, and `THIRD_PARTY_NOTICES.md` names each
one.
