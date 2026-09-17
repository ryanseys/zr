# ze0

**A Ruby compiler, written in Ruby.** ze0 compiles Ruby programs to
native binaries and WebAssembly modules. A compiled program answers
exactly what ruby 4.0.6 answers. When ze0 cannot promise that for a
program, it refuses to compile it, and names the line.

```console
$ cat hello.rb
puts "Hello, #{ARGV.first || "world"}!"

$ ze0 build hello.rb -o hello
$ ./hello Ruby
Hello, Ruby!
```

The compiler, the runtime, the core library, the parser and the garbage
collector are all Ruby. There is no C, Rust or assembler in the
repository.

## Install

```console
$ gem install ze0
```

You need:

- ruby 4.0.6, or a later 4.0 release;
- [wasmtime](https://wasmtime.dev), to run WebAssembly modules;
- OpenSSL 3 (`brew install openssl@3`), only for a macOS program that
  requires `openssl`. The binary opens the library when that `require`
  runs, and raises `LoadError` when the library is absent.

The install compiles nothing. ze0 links a macOS binary itself, so it
needs no C compiler and no linker.

## Use

```console
$ ze0 run app.rb                              # compile, run, and clean up
$ ze0 build app.rb -o app                     # a native binary
$ ze0 build app.rb -o app.wasm --emit wasm    # a WASI module
$ ze0 build app.rb -o app --target aarch64-linux-musl
$ ze0 targets                                 # what this machine can build
```

A binary holds your program, Ruby's core library and the runtime. It
needs no ruby and no gems to run.

New to ze0? Start with the tutorial
[Compile your first program](docs/tutorials/compile-your-first-program.md).

## What it builds

| Target | Output | Built on |
|---|---|---|
| `aarch64-apple-darwin` | native binary | an Apple Silicon Mac |
| `aarch64-linux-musl` | static binary | aarch64 Linux, or any host with a musl cross toolchain |
| `wasm32-wasi` | WASI module | any host |

Some features depend on the target. `eval` of a string needs macOS,
and fibers, threads and ractors are not available in a WASI module. See
[Targets](docs/reference/targets.md).

## How it works

```
app.rb ─► prism ─► HIR ─► IR ─┬─► aarch64 machine code ─► binary
                              └─► WebAssembly ─► WASI module
```

- **prism** parses the program. It is a Ruby port of the parser that
  ruby itself uses.
- **The HIR** is the program as a plain tree: desugared, with names
  resolved. A form ze0 cannot compile is refused here.
- **The IR** is one SSA form that every backend reads.
- **The runtime** is compiled into every program: a kernel in a typed
  dialect of Ruby, and the core library in ordinary Ruby.

ruby 4.0.6 is the only source of right answers. Every test program
carries ruby's recorded output, and ze0 must match it byte for byte.

Read more in [Architecture](docs/explanation/architecture.md) and
[The contract](docs/explanation/the-contract.md).

## Contribute

```console
$ git clone https://github.com/ryanseys/ze0.git
$ cd ze0
$ bundle install
$ rake test:spec FILTER=blocks  # Ruby held to ruby, program by program
$ rake test:unit                # ze0's own internals
```

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

ze0 is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses, and `THIRD_PARTY_NOTICES.md` names each
one.
