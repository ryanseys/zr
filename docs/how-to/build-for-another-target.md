# How to build for another target

This guide shows you how to build a program for a target that is not
the default: a WebAssembly module, an object file, or a Linux binary.
For all the targets, read [Targets](../reference/targets.md).

## See what this host can build

```console
$ zr doctor
...
ok    target             aarch64-apple-darwin   binary, obj; this host: binary, obj
warn  target             aarch64-linux-musl     binary, obj; this host: obj
ok    target             wasm32-wasi            wasm; this host: wasm
...
```

Each `target` line shows the outputs that zr can make for a target,
and after `this host:`, the outputs that this host can make now, with
the tools that it has. A Linux binary needs a musl cross toolchain.

## Build a WebAssembly module

Add `--emit wasm`. Any host can do this:

```console
$ zr build app.rb -o app.wasm --emit wasm
$ wasmtime app.wasm
```

If the program reads files, give wasmtime the directory:

```console
$ wasmtime run --dir . app.wasm
```

`zr run --emit wasm app.rb` builds the module and runs it this way.

A module cannot do everything that a binary can. `Fiber`, `Thread` and
FFI need things that WASI does not have. zr tells you when the program
uses them.

## Build an object file

Add `--emit obj`. Any host can do this too:

```console
$ zr build app.rb -o app.o --emit obj
$ zr build app.rb -o app.o --emit obj --target aarch64-linux-musl
```

The first command writes a Mach-O object, and the second an ELF object.
The object contains the program's own code. It does not contain the
runtime, which zr keeps as a different object in its cache.

## Build a static Linux binary

Give the target with `--target`:

```console
$ zr build app.rb -o app --target aarch64-linux-musl
```

This needs one of these:

- an aarch64 Linux host with musl's `cc`, for example Alpine Linux, or
- a host with a cross toolchain named `aarch64-linux-musl-gcc` on the
  `PATH`.

The binary is static, so it runs on any aarch64 Linux. `zr run` does
not work with a cross toolchain, because this host cannot run the
binary. Copy the binary to a Linux machine and run it there.
