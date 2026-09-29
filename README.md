# zr

**A Ruby compiler, written in Ruby.** zr compiles Ruby programs to
native binaries and WebAssembly modules. A compiled program gives
exactly the output that ruby 4.0.7 gives. When zr cannot promise this
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

> **Status: pre-1.0.** zr compiles large programs, bundler among them,
> and its tests hold every answer to ruby 4.0.7's. The command line and
> the environment variables can change in a minor release until 1.0.
> See [the changelog](CHANGELOG.md).

## Install

```console
$ gem install zr
$ zr doctor          # what this host has, and what zr can do here
```

You need:

- ruby 4.0.7, or a later 4.0 release. zr checks its output against
  ruby 4.0.7, and gives a warning on a later 4.0 release. The gem has
  no dependencies: it carries ruby 4.0.7's standard library itself, so
  the install downloads only zr;
- [wasmtime](https://wasmtime.dev), to run WebAssembly modules;
- OpenSSL 3 (`brew install openssl@3`), only for a macOS program that
  requires `openssl`.

The install compiles nothing. zr links a macOS binary itself, so it
needs no C compiler and no linker. The first build on a machine builds
zr's runtime into a cache (some minutes), and an Apple Silicon Mac
then builds a compiled copy of zr for faster builds (some minutes;
`ZR_COMPILED=0` skips it). `zr cache` shows the cache, and
`zr cache clean` frees it.

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

On a host that cannot run a macOS arm64 binary (Linux, an Intel Mac),
add `--emit wasm` and run the module with wasmtime:
`zr run --emit wasm hello.rb Ruby`.

A binary contains your program, Ruby's core library and the runtime.
It needs no ruby and no gems to run. `zr` exits with status 2 for a
usage error and 3 when it refuses a program; see
[The `zr` command](docs/reference/cli.md).

New to zr? Start with the tutorial
[Compile your first program](docs/tutorials/compile-your-first-program.md),
and read [Questions and answers](docs/explanation/faq.md).

## What it builds

| Target | Output | Built on |
|---|---|---|
| `aarch64-apple-darwin` | native binary | any host |
| `aarch64-linux-musl` | static binary | aarch64 Linux, or a host with a musl cross toolchain |
| `wasm32-wasi` | WASI module | any host |

Some features depend on the target. For example, a WASI module has no
fibers, threads or ractors. See [Targets](docs/reference/targets.md).

## Limits

- **Hosts.** zr builds no x86_64 or Windows binary, and no glibc Linux
  binary. Any host builds WASI modules and objects.
- **Size.** A binary contains the whole runtime: 27 MB for "hello
  world", 46 MB as a WASI module, and about 110 MB for a program that
  calls `eval`, which carries the compiler.
- **Libraries.** A program can require all of ruby 4.0.7's library,
  and a pure-Ruby gem through a literal `$LOAD_PATH`. A gem with a C
  extension works only if zr has a Ruby port of its C. See
  [How to use a library or a gem](docs/how-to/use-a-library-or-gem.md).
- **Refusals.** A few forms and libraries are refused at build time.
  [What zr supports](docs/reference/support.md) lists them, and
  [Differences from ruby](docs/reference/differences-from-ruby.md) lists
  the other differences, all on purpose.

## Performance

Over 54 benchmark programs, a binary takes 0.41 times ruby's time and
0.59 times YJIT's, and an empty program starts in 11 ms against ruby's
33 ms. Arithmetic on large bignums and Regexp are slower than in ruby.
[Performance](docs/explanation/performance.md) has every program and
the build times.

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

ruby 4.0.7 is the only source of expected outputs. zr must match
ruby's output byte for byte. See
[Architecture](docs/explanation/architecture.md) and
[The contract](docs/explanation/the-contract.md).

## Contribute

The full test suite needs an Apple Silicon Mac. On Linux you can work
on the `wasm32-wasi` target (`TARGET=wasm32-wasi bin/test ...`); see
[How to test on another target](docs/how-to/test-on-another-target.md).

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup                        # install the gems and build the runtime (a few minutes)
$ bin/test test/spec/core/string   # the tests in one directory
$ bin/test --changed               # the tests that your change can reach
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

See [How to release zr](docs/how-to/release.md).

## License

zr is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses. `THIRD_PARTY_NOTICES.md` lists each
one.
