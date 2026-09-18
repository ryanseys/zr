# Targets

A target is what ze0 emits. The gem itself runs on any host that has
ruby 4.0.6. `Ze0::Target` (`lib/ze0/target.rb`) defines each target.

| Target | Outputs | Object format | Runtime layers |
|---|---|---|---|
| `aarch64-apple-darwin` (default on a Mac) | binary, object | Mach-O | `os/darwin`, `arch/aarch64` |
| `aarch64-linux-musl` | binary, object | ELF | `os/linux`, `arch/aarch64` |
| `wasm32-wasi` | WASI module | wasm | `os/wasi`, `arch/wasm32` |

## What each host can build

| Output | Host requirement |
|---|---|
| `aarch64-apple-darwin` binary | any host: ze0 links it |
| `aarch64-linux-musl` binary | an aarch64 Linux host with musl's `cc`, or any host with `aarch64-linux-musl-gcc` on the `PATH` |
| WASI module | any host |
| Mach-O or ELF object | any host |

`ze0 run` runs a binary only on the target's own host. On a host that
cannot link a binary, `ze0 build` without `--emit` exits with status 3.

## Differences between targets

| | darwin | linux-musl | wasi |
|---|---|---|---|
| Linker | ze0's own (`Obj::MachO::Executable`) | `cc -static` | none: one module |
| `Fiber`, `Thread`, `Ractor` | yes | yes | no: a module has one stack; `Fiber.new` raises `FiberError` |
| `eval` of a string | yes | no: a static binary cannot load code | no |
| FFI (`ffi`, `fiddle`) | yes | no | no |
| Preemption | a timer thread | a timer thread | a count at each safe point |
| Answer held to | what ruby recorded | the same, or a spec's `linux:` | the same, or a spec's `wasi:` |

## Runtime layers

The portable runtime calls a fixed set of OS functions, which
`rt/kernel/os.rb` lists. Each OS layer implements all of them:

| Directory | Holds |
|---|---|
| `rt/kernel/os/<os>/` | the kernel's OS calls: errno, descriptors, stacks, signals, JIT mapping |
| `rt/kernel/arch/<arch>/` | the machine context a task switch saves |
| `rt/core/os/<os>/` | the numbers the OS gives errno, IO, File and Process constants |
| `rt/ext/os/<os>/` | extension tables (fcntl, etc, socket) and the eval description |

The table files come from the ruby of that OS (`rake tables`).
