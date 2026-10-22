# Roadmap

The work that is planned after the first release. A plan is not a
promise: an item can move to a later version, or go. What each release
did is in [the changelog](../../CHANGELOG.md).

## 0.2

- `--gems host`: build with the gems that the host's rubygems has
  installed.
- `zr gem install`: a gem home of zr's own, for gems that a build reads.
- racc's C port (`lib/zr/runtime/ext/racc/cparse.so.rb`): a
  `require "racc/cparse"` with no `racc/parser` before it raises
  `NameError` for `Racc::VERSION`, which ruby's C does not read. Until
  this is fixed, do not build or run racc programs locally: a check of
  it stopped a 16 GB Mac.
- Fibers and threads on wasm32-wasi: a module cannot allocate a stack
  to switch to, so no Fiber or Thread starts there, and the program
  tests that need one skip (`fibers`). CRuby's WASI build runs the
  module through binaryen's Asyncify (`wasm-opt --asyncify`), which
  saves and restores the wasm stack in linear memory. zr can do the
  same as a pass on its own modules.
- crypt(3) on wasm32-wasi: zr's WASI libc has none, so `String#crypt`
  raises "invalid salt" there, and four program tests are in the wasm
  baseline. A port of musl's `crypt_des.c` and `crypt_md5.c` would give
  the answers of the linux-musl recordings that a wasm run reads.
- Deep block recursion on wasm32-wasi: the shadow stack holds a method
  recursion 10,000 deep, but a block takes more of it for each level,
  and a bigger one needs an engine stack past the host thread's 8 MiB.
  Giving wasmtime a bigger thread stack (`rlimit_stack`) would let both
  grow.
- `Ractor.shareable_proc` of a block that the eval walker made: the
  block's captured locals have no scope that the check can read, and
  the program stops with a segmentation fault (wasm32-wasi, and
  `ZR_EVAL=walk`).
- A file that the eval walker loads at run time sends
  `require "rbconfig"` through the program's own `Kernel#require`,
  which ruby loaded at boot, so a program that traces its requires sees
  one more.
