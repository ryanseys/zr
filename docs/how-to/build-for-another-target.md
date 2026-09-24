# How to build for another target

This guide shows you how to build a program for a target other than
the default: a WebAssembly module, an object file, or a Linux binary.
To see the full list of targets, read [Targets](../reference/targets.md).

## See what this machine can build

```console
$ zr targets
TARGET                 OUTPUTS            ON THIS HOST
aarch64-apple-darwin   binary, obj        binary, obj
aarch64-linux-musl     binary, obj        obj
wasm32-wasi            wasm               wasm
```

The `OUTPUTS` column says what zr can make for a target. The
`ON THIS HOST` column says what this machine can make now, with the
tools it has. A Linux binary needs a musl cross toolchain.

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

A module cannot do everything a binary can. `Fiber`, `Thread`,
`eval` and FFI need things WASI does not have, and zr says so when
the program reaches them.

## Build an object file

Add `--emit obj`. Any host can do this too:

```console
$ zr build app.rb -o app.o --emit obj
$ zr build app.rb -o app.o --emit obj --target aarch64-linux-musl
```

The first command writes a Mach-O object, the second an ELF object.
The object holds the program's own code. It does not hold the runtime,
which zr keeps as an object of its own in its cache.

## Build a static Linux binary

Name the target with `--target`:

```console
$ zr build app.rb -o app --target aarch64-linux-musl
```

This needs one of these:

- an aarch64 Linux host with musl's `cc`, for example Alpine Linux, or
- any host with a cross toolchain named `aarch64-linux-musl-gcc` on the
  `PATH`.

The binary is static, so it runs on any aarch64 Linux. `zr run` does
not work with a cross toolchain, because this host cannot run the
binary. Copy it to a Linux machine and run it there.
