# Why zr has no C

zr has no C or assembler source of its own, and it includes no C
library. The parser, the regular expression engine, zlib, the collector
and the code generator are all Ruby. This page explains why, and how
the ports stay correct.

## The ports

| Library | Role | In zr |
|---|---|---|
| prism 1.9.0 | the parser that ruby uses | a Ruby port in `runtime/ext/prism/ruby`, under prism's own Ruby half |
| Onigmo | CRuby 4.0.6's regular expression engine | a Ruby port: the pattern compiler in `runtime/core/regexp/onig/`, and the matcher in the machine dialect in `runtime/kernel/onig_*.rb` |
| zlib 1.3.1 | compression | a port in the machine dialect, `runtime/kernel/zlib_*.rb` |

## Why no C

**One language.** A Ruby programmer can read and change every part of
zr. Most of the project's readers cannot work on a C dependency.

**Every target.** C must be compiled for each target, with a C
toolchain for that target. A C library needs a wasm32 toolchain and a
libc for WebAssembly. The Ruby ports need nothing. zlib, `Regexp` and
the parser all work in a WASI module.

**A simpler install.** A gem with C compiles it at install time, and a
host without a C compiler cannot install it. The zr install compiles
nothing.

**Eval.** A compiled program that evals includes the compiler, and the
compiler parses. With prism in Ruby, the parser inside the binary is
the same code as the parser on the host.

## Why port, and not rewrite

Each engine is a port of the C that ruby uses, not a new design. The
contract is ruby's exact output. The fastest way to give the same
results as prism, Onigmo and zlib is to follow their code: the same
states, the same tables, the same order of checks, and the same error
messages.

A port keeps the structure of its C file. Thus you can compare a
function with its original, side by side.

## How the ports stay correct

Each port has its own area in `test/spec/stdlib/<gem>/`, checked
program by program against ruby.

A port also runs on CRuby on the host. Thus two ports are also checked
against ruby's own C, in one process, object by object:

- `test/unit/prism_test.rb` compares every node, token, comment and
  diagnostic over prism's fixtures and zr's own source files, checks
  the writer of `Prism.dump` against the C byte for byte, and runs
  prism 1.9.0's own test suite on the port.
- `test/unit/regexp_diff_test.rb` compares errors, warnings and the
  offsets of every capture over a committed sample of collected and
  fuzzed patterns.

The compiler on the host uses the prism port too, so every build of zr
tests it.

Kernel code, such as the zlib port, does not run directly on CRuby.
The tests compile it and load it into the test process; see
[Running kernel code on the host](the-runtime.md#running-kernel-code-on-the-host).

## What is not Ruby

zr uses some tools and libraries that are not Ruby, and that it does
not own:

- `cc`, to link a static Linux binary;
- libSystem on macOS, and musl on Linux;
- wasmtime, to run modules;
- libffi, which the `ffi` gem loads at run time.
