# Why ze0 has no C

ze0 has no C, Rust or assembler source of its own, and it vendors no C
library. The parser, the regular expression engine, zlib, the
collector and the code generator are all Ruby. This page explains why,
and how the ports stay correct.

## What was C, and what it is now

| Library | Role | Now |
|---|---|---|
| prism 1.9.0 | the parser ruby uses | a Ruby port in `rt/ext/prism/ruby`, under prism's own Ruby half |
| Onigmo | CRuby 4.0.6's regular expression engine | a Ruby port: the pattern compiler in `rt/core/regexp/onig/`, the matcher in the kernel dialect in `rt/kernel/onig_*.rb` |
| zlib 1.3.1 | compression | a port in the kernel dialect, `rt/kernel/zlib_*.rb` |

## Why remove the C

**One language.** A Rubyist can read and change every part of ze0. A C
dependency is a part of the project that most of its readers cannot
work on.

**Every target.** C must be compiled for each target, with a C
toolchain for that target. WebAssembly made this plain: a vendored C
library needs a wasm32 toolchain and libc, and the Ruby ports need
nothing. zlib, `Regexp` and the parser all work in a WASI module.

**A simpler install.** With C in the gem, `gem install` compiled it,
and a host without a C compiler could not install everything. Now the
install compiles nothing.

**Eval.** A compiled program that evals carries the compiler, and the
compiler parses. With prism in Ruby, the parser inside the binary is
the same code as the parser on the host.

## Why port, and not rewrite

Each engine is a port of the C that ruby itself uses, not a new
design. The contract is ruby's exact answer, and the fastest way to
answer as prism, Onigmo and zlib answer is to follow their code: the
same states, the same tables, the same order of checks, and the same
error messages.

A port keeps the structure of its C file. That makes it possible to
check a function against its original side by side.

## How the ports stay correct

Each port answers for itself in `test/spec/stdlib/<gem>/`, program by
program, against what ruby answered.

A port also runs on host CRuby, so two of them are held a second way --
beside ruby's own C, in one process, object for object:

- `test/unit/prism_test.rb` compares every node, token, comment and
  diagnostic over prism's fixtures and ze0's own source files, holds
  `Prism.dump`'s writer to the C byte for byte, and runs prism 1.9.0's
  own test suite on the port.
- `test/unit/regexp_diff_test.rb` compares errors, warnings and every
  capture's offsets over a committed sample of harvested and fuzzed
  patterns.

The host compiler uses the prism port too, so every build of ze0 is a
test of it.

## What remains outside

ze0 still uses some tools and libraries that are not Ruby, and does not
own them:

- `cc`, to link a static Linux binary;
- libSystem on macOS, and musl on Linux;
- wasmtime, to run modules;
- libffi, which the `ffi` gem loads at run time.
