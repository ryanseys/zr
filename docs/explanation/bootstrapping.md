# Bootstrapping

ze0 is written in Ruby, and it compiles Ruby. So it can compile itself.
This page explains why that matters, and what `rake stage1` and
`rake stage2` check.

## The stages

- **Stage 0** is ze0 running on CRuby: `exe/ze0`.
- **Stage 1** is the compiler that stage 0 builds: a native binary of
  `exe/ze0` itself. There is no second program written for the ladder;
  the binary is the same `ze0` a user runs, with the same commands.
- **Stage 2** is the compiler that stage 1 builds from the same source,
  by running `tmp/stage1/ze0 build exe/ze0 -o tmp/stage2/ze0`.

Under CRuby, `exe/ze0` starts itself again with the collector limits a
compile wants (`Ze0::CLI.tune!`). A compiled `ze0` does not: only CRuby's
collector reads those limits, and a ze0 binary's `RbConfig.ruby` names
ze0's own interpreter, not the running process.

If ze0 compiles its own source correctly, stage 1 behaves as stage 0
does. Then stage 1 builds stage 2 with the same decisions that stage 0
made building stage 1, and the two binaries are the same bytes. That
is a *fixed point*.

## What `stage1` checks

`rake stage1` runs stage 0 twice, in two processes with two separate
caches, and compiles the compiler to an object each time. It compares
the two compiler objects and the two runtime objects byte for byte.

This checks that the compiler is deterministic. A build must not depend
on hash order, object addresses, the time, or the order a directory
lists its files. If one does, two builds can differ, and a bug can come
and go between them. `stage1` is quick enough to run after any change
to the compiler.

## What `stage2` checks

`rake stage2` builds stage 1 with ruby, then runs stage 1 to build
stage 2, and compares the two binaries. ze0's own linker links both,
and stage 2's link runs inside the compiled compiler, so the check
covers the linker too. The UUID and the signature are left out of the
comparison, because under `ZE0_LINK=cc` the system linker writes them
and no input decides them.

This is a much larger test than any spec or program. The compiler is
tens of thousands of lines of real Ruby: the prism port, the HIR build,
the lowering, the IR passes, the backend, the object writers and the
linker. If compiled ze0 answers differently from ze0 on CRuby anywhere
on that path, the bytes differ.

It is also slow. Stage 1 runs the whole compiler as compiled code, and
building stage 2 takes several minutes and several gigabytes. Stage 1
builds stage 2 in one process: a forked worker of the compiled compiler
holds the compiler's whole heap, and six of them have driven a
sixteen-gigabyte machine into swap. Set `ZE0_JOBS` to let it fork.

## Why self-hosting is worth it

A Ruby compiler written in Ruby has one language from top to bottom.
A Rubyist can read the parser port, the collector and the code
generator without leaving Ruby. And the compiler is its own best test:
every feature of Ruby that the compiler uses must work in a compiled
program first.
