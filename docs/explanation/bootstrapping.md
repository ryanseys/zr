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

zr compiles itself only to check itself. `zr-dev stage 1` and
`zr-dev stage 2` build stage 1 in `tmp/stage1/zr` (`tool/stage.rb`), and `zr-dev compile --zr` builds
it in `tmp/compile/zr` to time it (`tool/compile.rb`). The `zr` command
does not use stage 1: ruby runs every command of `exe/zr`.

## What `stage 1` checks

`zr-dev stage 1` runs stage 0 once and builds stage 1 in
`tmp/stage1/zr`, with a cache of its own in `tmp/stage1/cache`. It
checks that zr compiles its own source with no refusal.

The binary and the cache stay after the run. A stamp,
`tmp/stage1/zr.sources`, names the git trees of `exe`, `lib`, `vendor`
and `Gemfile.lock` that the binary was built from. When those paths
have no uncommitted change and the stamp matches, `zr-dev stage 1` and
`zr-dev stage 2` use the binary again and do not build it. Only one
`zr-dev stage` runs at a time (`tmp/stage.lock`).

Stage 1 does not compare bytes. Stage 2 does: if a build depended on
hash order, object addresses, the time, or the order in which a
directory lists its files, the binary that stage 1 builds would not
be the binary that ruby builds.

## What `stage 2` checks

`zr-dev stage 2` builds stage 1 with ruby, then runs stage 1 to build
stage 2, and compares the two binaries. zr's own linker links both,
and the link of stage 2 runs inside the compiled compiler, so the check
covers the linker too. The comparison does not include the UUID and
the signature, because under `ZR_LINKER=cc` the system linker writes
them and no input decides them.

This test is much larger than any program test. The compiler is
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
