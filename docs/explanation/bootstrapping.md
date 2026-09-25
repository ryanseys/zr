# Bootstrapping

zr is written in Ruby, and it compiles Ruby. Thus it can compile
itself. This page explains why that is important, and what
`zr-dev stage 1` and `zr-dev stage 2` check.

## The stages

- **Stage 0** is zr on CRuby: `exe/zr`.
- **Stage 1** is the compiler that stage 0 builds: a native binary of
  `exe/zr`. It is the same `zr` that a user runs, with the same
  commands. No other program is written for the stages.
- **Stage 2** is the compiler that stage 1 builds from the same source,
  with `tmp/stage1/zr build exe/zr -o tmp/stage2/zr`.

Under CRuby, `exe/zr` starts itself again with the collector limits
that a compile needs (`Zr::CLI.tune!`). A compiled `zr` does not do
this: only CRuby's collector reads those limits.

If zr compiles its own source correctly, stage 1 behaves as stage 0
does. Then stage 1 builds stage 2 with the same decisions that stage 0
made when it built stage 1, and the two binaries are the same bytes.
This is a *fixed point*.

The compiled compiler that `rake build:self` builds, and that `exe/zr`
can use for a build (`ZR_COMPILED`), is stage 1.

## What `stage 1` checks

`zr-dev stage 1` runs stage 0 two times, in two processes with two
caches, and compiles the compiler to an object each time. It compares
the two compiler objects and the two runtime objects byte for byte.

This checks that the compiler is deterministic. A build must not
depend on hash order, object addresses, the time, or the order in
which a directory lists its files. If a build depends on one of these,
two builds can be different, and a bug can come and go between them.
`zr-dev stage 1` is fast enough to run after any change to the compiler.

`zr-dev repro` checks a related property: two copies of the tree at
two paths, with a different home, time zone, locale and job count,
build one program to the same bytes.

## What `stage 2` checks

`zr-dev stage 2` builds stage 1 with ruby, then runs stage 1 to build
stage 2, and compares the two binaries. zr's own linker links both,
and the link of stage 2 runs inside the compiled compiler, so the check
covers the linker too. The comparison does not include the UUID and
the signature, because under `ZR_LINKER=cc` the system linker writes
them and no input decides them.

This test is much larger than any spec or program. The compiler is
tens of thousands of lines of real Ruby: the prism port, the HIR build,
the lowering, the IR passes, the backend, the object writers and the
linker. If compiled zr gives a different result from zr on CRuby
anywhere on that path, the bytes are different.

It is also slow. Stage 1 runs the whole compiler as compiled code, and
the build of stage 2 takes about ten minutes and 5 GB of memory. Stage
1 builds stage 2 in one process: a forked worker of the compiled
compiler contains the compiler's whole heap, and six of them made a
16 GB machine swap. Set `ZR_JOBS` to let it fork.

## Why self-hosting is worth it

A Ruby compiler written in Ruby has one language from top to bottom.
A Ruby programmer can read the parser port, the collector and the code
generator without another language. And the compiler is its own best
test: every feature of Ruby that the compiler uses must work in a
compiled program first.
