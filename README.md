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
> See [the changelog](https://github.com/ryanseys/zr/blob/v0.1.0/CHANGELOG.md).

## Install

```console
$ ruby -v            # 4.0.7, or a later 4.0 release
$ gem install zr
$ zr doctor          # what this host has, and what zr can do here
$ zr run hello.rb
```

[How to install zr](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/install.md) shows how to get ruby
4.0.7, and what to do when a step fails. You need:

- ruby 4.0.7, or a later 4.0 release. zr checks its output against
  ruby 4.0.7, and gives a warning on a later 4.0 release. The gem has
  no dependencies: it carries ruby 4.0.7's standard library itself, so
  the install downloads only zr;
- a host that runs the binaries: an Apple Silicon Mac with macOS 14 or
  later, or aarch64 Linux. Any other host builds WebAssembly modules;
- [wasmtime](https://wasmtime.dev), to run WebAssembly modules;
- OpenSSL 3 (`brew install openssl@3`), only for a macOS program that
  requires `openssl`.

The install compiles nothing. zr links a macOS binary itself, so it
needs no C compiler and no linker. The first build on a machine builds
zr's runtime into a cache (some minutes), and says so when it starts. `zr cache size` shows the cache, and
`zr cache clean --all` frees all of it.

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
usage error or a bad `ZR_*` value, 3 when it refuses a program, and 130
for Ctrl-C; see
[The `zr` command](https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/cli.md).

New to zr? Start with the tutorial
[Compile your first program](https://github.com/ryanseys/zr/blob/v0.1.0/docs/tutorials/compile-your-first-program.md),
and read [Questions and answers](https://github.com/ryanseys/zr/blob/v0.1.0/docs/explanation/faq.md).

## What it builds

| Target | Output | Built on |
|---|---|---|
| `aarch64-apple-darwin` | native binary for macOS 14 or later | any host |
| `aarch64-linux-musl` | static binary for any aarch64 Linux | aarch64 Linux with musl's `cc` (Alpine's, or `musl-gcc`), or a host with a musl cross toolchain |
| `wasm32-wasi` | WASI module | any host |

Some features depend on the target. For example, a WASI module has no
fibers, threads or ractors. See [Targets](https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/targets.md).

## Limits

- **Hosts.** zr builds binaries for arm64 only: an Apple Silicon Mac,
  and aarch64 Linux (a static musl binary, which also runs on a glibc
  Linux). It builds no x86_64 or Windows binary. Any host builds WASI
  modules and objects.
- **Size.** A binary contains the whole runtime: 27 MB for "hello
  world", 46 MB as a WASI module, and about 110 MB for a program that
  calls `eval`, which carries the compiler.
- **Libraries.** A program can require all of ruby 4.0.7's library,
  and a pure-Ruby gem through a literal `$LOAD_PATH`. A gem with a C
  extension works only if zr has a Ruby port of its C. See
  [How to use a library or a gem](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/use-a-library-or-gem.md).
- **Refusals.** A few forms and libraries are refused at build time.
  [What zr supports](https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/support.md) lists them, and
  [Differences from ruby](https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/differences-from-ruby.md) lists
  the other differences, all on purpose.

## Performance

Over the benchmark programs, a binary takes less time than ruby and
than ruby with YJIT (the geometric mean), and it starts faster. Arithmetic on large bignums
and Regexp are slower than in ruby.
[Performance](https://github.com/ryanseys/zr/blob/v0.1.0/docs/explanation/performance.md) has the numbers for
every program, and the build times.

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
  typed Ruby (plain Ruby syntax, machine types), and the core
  library in ordinary Ruby.

ruby 4.0.7 is the only source of expected outputs. zr must match
ruby's output byte for byte. See
[Architecture](https://github.com/ryanseys/zr/blob/v0.1.0/docs/explanation/architecture.md) and
[The contract](https://github.com/ryanseys/zr/blob/v0.1.0/docs/explanation/the-contract.md).

## Contribute

The full test suite needs an Apple Silicon Mac. On Linux you can work
on the `wasm32-wasi` target (`ZR_TARGET=wasm32-wasi bin/minitest ...`); see
[How to test on another target](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/test-on-another-target.md).

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup               # install the gems and build the runtime (a few minutes)
$ ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
                          # the program tests in one directory
$ bin/zr-dev affected     # the tests that your change can reach
$ bin/minitest            # all the tests: unit, programs
```

`bin/minitest` builds the runtime again when a change under `lib/` or
`lib/zr/runtime/` makes it out of date. Read [CONTRIBUTING.md](https://github.com/ryanseys/zr/blob/v0.1.0/CONTRIBUTING.md)
before you open a pull request, and the tutorial
[Add your first program test](https://github.com/ryanseys/zr/blob/v0.1.0/docs/tutorials/add-your-first-program-test.md).

## Development

```console
$ rake lint       # RuboCop (.rubocop.yml)
$ rake build      # build the runtime for this host
$ bin/console     # IRB with zr loaded
$ rake -T         # every rake task
$ ruby tool/zr-dev.rb help   # every maintainer tool
```

See [How to run the tests](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/run-the-tests.md) and
[Tools](https://github.com/ryanseys/zr/blob/v0.1.0/docs/reference/tools.md). All the
documentation is in [`docs/`](https://github.com/ryanseys/zr/blob/v0.1.0/docs/README.md).

## Release

See [How to release zr](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/release.md).

## License

zr is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses. `THIRD_PARTY_NOTICES.md` lists each
one.
