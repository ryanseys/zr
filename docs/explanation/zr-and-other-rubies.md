# zr and other Rubies

This page tells how zr is different from other projects that run or
compile Ruby. Each project answers a different question. Read each
project's own documentation for the full facts; this page gives only
the difference that matters when you choose.

## The question zr answers

zr answers: "Can this Ruby program be one native binary or one
WebAssembly module, with no ruby to install, that gives exactly
ruby 4.0.7's output?" When zr cannot promise the same output for a
form, it refuses the program by name, and does not guess
([the contract](the-contract.md)). zr is written in Ruby, has no C,
and compiles itself.

## Comparison

| Project | What it is | How it runs your code | Output of a program |
|---|---|---|---|
| **zr** | A compiler written in Ruby | Ahead of time, to a native binary (macOS arm64, Linux arm64 musl) or a WASI module; the runtime and core library are compiled in | ruby 4.0.7's, byte for byte, or a refusal at build time |
| [CRuby](https://www.ruby-lang.org) with [YJIT](https://docs.ruby-lang.org/en/master/yjit/yjit_md.html) | The reference implementation | Bytecode interpreter, with a JIT compiler | The reference |
| [ruby.wasm](https://github.com/ruby/ruby.wasm) | CRuby compiled to WebAssembly | The CRuby interpreter runs in the module, beside your source | CRuby's; some features that WASI does not have are missing |
| [TruffleRuby](https://github.com/oracle/truffleruby) | A Ruby on GraalVM | A JIT compiler on a JVM, or a native image of the interpreter | Aims at CRuby's; a separate implementation |
| [JRuby](https://github.com/jruby/jruby) | A Ruby on the JVM | Interpreter and JIT on the JVM | Aims at CRuby's; a separate implementation |
| [mruby](https://github.com/mruby/mruby) | A small Ruby for embedding | Bytecode interpreter in a small C library | A smaller language and library than CRuby's |
| [Natalie](https://github.com/natalie-lang/natalie) | A Ruby compiler in Ruby and C++ | Ahead of time, through C++ | Aims at CRuby's; work in progress |
| [Spinel](https://github.com/matz/spinel) | A Ruby AOT compiler in C | Ahead of time: whole-program type inference, then C and `cc` | For the subset that it compiles |

## When to use zr

- You want to ship one file that runs without ruby, and the program
  must behave as it does under ruby 4.0.7.
- You want a WebAssembly module of a Ruby program without an
  interpreter inside it.
- You want a build that tells you at build time which parts of your
  program it cannot promise, rather than a difference at run time.

## When to use something else

- Your program needs a gem with a C extension that zr has not ported
  and cannot run: one that calls a function of ruby's C API that zr
  does not have, or one that needs OpenSSL in a Linux binary
  ([How to use a C extension](../how-to/use-a-c-extension.md)).
  Or it needs another ruby version than 4.0.7. Use CRuby.
- You need an x86_64 or Windows binary. zr does not build one yet
  ([Targets](../reference/targets.md)).
- You want to run Ruby in a browser. zr builds WASI modules for an
  engine such as wasmtime; ruby.wasm also builds for the browser.
- You embed a scripting language in a C program. mruby does this.
- You run a long-lived server and want the fastest steady state. A JIT
  (YJIT, TruffleRuby, JRuby) can be faster than zr on some programs; see
  [Performance](performance.md).
