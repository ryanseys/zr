# Bootstrapping

ze0 is written in Ruby, and it compiles Ruby. So it can compile itself.
This page explains why that matters, and what `bin/ze0 stage1` and
`bin/ze0 stage2` check.

## The stages

- **Stage 0** is ze0 running on CRuby: `bin/ze0`.
- **Stage 1** is the compiler that stage 0 builds: a native binary of
  `tools/stage.rb`, which is ze0's compiler as a program.
- **Stage 2** is the compiler that stage 1 builds from the same source.

If ze0 compiles its own source correctly, stage 1 behaves as stage 0
does. Then stage 1 builds stage 2 with the same decisions that stage 0
made building stage 1, and the two binaries are the same bytes. That
is a *fixed point*.

## What `stage1` checks

`bin/ze0 stage1` runs stage 0 twice, in two processes with two separate
caches, and compiles the compiler to an object each time. It compares
the two compiler objects and the two runtime objects byte for byte.

This checks that the compiler is deterministic. A build must not depend
on hash order, object addresses, the time, or the order a directory
lists its files. If one does, two builds can differ, and a bug can come
and go between them. `stage1` is quick enough to run after any change
to the compiler.

## What `stage2` checks

`bin/ze0 stage2` builds stage 1 with ruby, then runs stage 1 to build
stage 2, and compares the two binaries. The bytes that the system
linker writes and no input decides (on macOS, a UUID and a signature)
are left out of the comparison.

This is a much larger test than any corpus program. The compiler is
tens of thousands of lines of real Ruby: the prism port, the HIR build,
the lowering, the IR passes, the backend and the object writers. If
compiled ze0 answers differently from ze0 on CRuby anywhere on that
path, the bytes differ.

It is also slow. Stage 1 runs the whole compiler as compiled code, and
building stage 2 takes several minutes and several gigabytes.

## Why self-hosting is worth it

A Ruby compiler written in Ruby has one language from top to bottom.
A Rubyist can read the parser port, the collector and the code
generator without leaving Ruby. And the compiler is its own best test:
every feature of Ruby that the compiler uses must work in a compiled
program first.
