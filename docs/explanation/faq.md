# Questions and answers

## Why only ruby 4.0.7?

zr promises the output that ruby 4.0.7 gives. Each test compares zr's
output with a recording from that one ruby, and zr compiles that
ruby's own library, which zr carries, into each program. The host ruby
only runs the compiler, so zr also runs on a later 4.0 release, with a
warning: the programs that it builds still give ruby 4.0.7's answers.
A ruby outside 4.0 is refused. See
[ruby 4.0.7 is part of the toolchain](the-contract.md#ruby-407-is-part-of-the-toolchain).

## What happens when my program uses something zr does not support?

`zr build` stops with exit status 3, before it writes a file. The
message gives the file, the line and the column, the form, and the
source line with a caret under the form. zr does not build a binary
that can give an answer different from ruby's.
[What zr supports](../reference/support.md) lists the refused forms and
libraries.

## Can I use gems?

You can use every library that ruby 4.0.7 ships, and a pure-Ruby gem
that you add to `$LOAD_PATH` with a literal path. You cannot use a gem
that needs a C extension, unless zr has ported it (zr has ports of the
C of json, psych, zlib, digest, openssl, socket, stringio, strscan,
date, bigdecimal, nkf, ffi and others). See
[How to use a library or a gem](../how-to/use-a-library-or-gem.md).

## How large is a binary?

A binary contains the whole runtime and core library. For "hello
world", on the machine that measured it:

| Output | Size |
|---|---|
| `aarch64-apple-darwin` binary | 27 MB |
| `wasm32-wasi` module | 46 MB |
| a binary of a program that calls `eval` | about 110 MB (it contains the compiler) |

## How fast is it?

Over the benchmark programs that run long enough to measure, a binary
takes less time than ruby and than ruby with YJIT (the geometric mean),
and an empty program starts faster than ruby. Some programs are slower
than ruby, for example arithmetic on large bignums.
[Performance](performance.md) has the numbers for each program; a
tool writes that page from the last benchmark run.

## How long does a build take?

The first build on a machine builds the runtime and caches it: some
minutes on a Mac. After that, a small program builds in about half a
second, and a large one (all of bundler) in about six seconds. An
installed zr also builds a compiled copy of itself at its first build
(some minutes), which makes later builds faster; set `ZR_COMPILED=0`
to skip it. `zr cache clean` frees the cache of older versions.

## Which machines can build, and which can run the output?

Any host with ruby 4.0.7 can build a macOS arm64 binary, a WASI module
and an object file. Only an Apple Silicon Mac runs the macOS binary.
An `aarch64-linux-musl` binary needs a musl cross toolchain, or an
aarch64 Linux host with musl. zr does not build x86_64 or Windows
binaries yet. `zr targets` shows what this host can build. See
[Targets](../reference/targets.md).

## Does a binary need anything to run?

A macOS or Linux binary needs nothing: no ruby and no gems. A program
that requires `openssl` needs OpenSSL 3 on the machine that runs it.
A WASI module needs an engine such as [wasmtime](https://wasmtime.dev).

## Can I distribute the binaries that zr builds?

Yes. zr is MIT-licensed, and a binary contains parts under other
licenses too (Onigmo, MT19937, Ryu, the Unicode data and ruby's own
code). Some of these licenses ask you to give their notices with a
binary copy. See
[What a compiled program contains](../../THIRD_PARTY_NOTICES.md#what-a-compiled-program-contains).

## Why does zr have no C?

So that `gem install zr` compiles nothing, the same source gives the
same bytes on every host, and zr can compile itself. See
[Why zr has no C](why-zr-has-no-c.md).

## My program gives a different answer from ruby. What do I do?

That is a defect in zr: zr must give ruby's answer or refuse. Reduce
the program to a few lines, and open an issue with the program, what
ruby prints, what the binary prints, and the output of `zr doctor`.
[How to debug a wrong answer](../how-to/debug-a-wrong-answer.md) helps
you find the cause.

## How does zr compare with TruffleRuby, mruby, ruby.wasm and others?

See [zr and other Rubies](zr-and-other-rubies.md).
