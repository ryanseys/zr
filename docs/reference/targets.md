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
| `eval` of a string | yes | yes | yes, by walking the tree |
| FFI (`ffi`, `fiddle`) | yes | no | no |
| Preemption | a timer thread | a timer thread | a count at each safe point |
| Answer held to | what ruby recorded | the same, or a spec's `linux:` | the same, or a spec's `wasi:` |

### What wasm does not answer, and why it stays that way

`test/baselines/wasm32-wasi.txt` names the end-to-end programs this
target is allowed to fail. Two groups of them are not work that is
waiting to be done.

**Fibers, threads and ractors.** Each needs a second machine stack to
switch onto, and a WASI module is given one, which the engine keeps
(`docs/explanation/threads-fibers-and-ractors.md`). Nothing the runtime
can call makes another. The answer is the **stack-switching proposal**,
which would give a module its own suspendable continuations; wasmtime
does not ship it, so `Fiber.new` raises `FiberError` here and the rows
for `fiber_resume` and `threads_join` stay until an engine does.

**Processes and signals.** WASI has no `fork`, no `exec` and no `kill`,
and no proposal is pending for any of them, so `spawn` and `Signal.trap`
stay on the baseline as well.

The other rows are work: a memory bound a 32-bit module runs into, a
socket table nobody has written, and `dlopen`, which wasm has no form
for.

A darwin or linux program that evals writes the machine code it
compiles into itself. A module's code is fixed when the engine
instantiates it, and WASI hands a guest no way to make a second one, so
a wasm program carries the same front end and walks the tree it builds.
It refuses a few forms by name where it stands, which
`docs/explanation/eval-in-a-compiled-program.md` lists.

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
