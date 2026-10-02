# Targets

A target is what zr builds for. The gem itself runs on any host with
ruby 4.0.7. `Zr::Target` (`lib/zr/target.rb`) defines each target.
`zr doctor` shows what this host can build.

| Target | Outputs | Object format | Runtime layers |
|---|---|---|---|
| `aarch64-apple-darwin` (the default on a Mac, and on a host that runs no target) | binary, object file | Mach-O | `os/darwin`, `arch/aarch64` |
| `aarch64-linux-musl` (the default on aarch64 Linux) | binary, object file | ELF | `os/linux`, `arch/aarch64` |
| `wasm32-wasi` | WASI module | wasm | `os/wasi`, `arch/wasm32` |

## What each host can build

| Output | Host requirement |
|---|---|
| `aarch64-apple-darwin` binary | any host: zr links it |
| `aarch64-linux-musl` binary | an aarch64 Linux host with musl's `cc`: Alpine's own, or on a glibc Linux the compiler that `CC` names, `aarch64-linux-musl-gcc` or `musl-gcc` (`apt install musl-tools`). Any other host needs `aarch64-linux-musl-gcc` on the `PATH`. |
| WASI module | any host |
| Mach-O or ELF object file | any host |

`zr run` runs a binary only on a host that can run it: an Apple Silicon
Mac for `aarch64-apple-darwin`, and any aarch64 Linux (musl or glibc)
for the static `aarch64-linux-musl` binary. On another host (x86_64
Linux, an Intel Mac), `zr run` stops, and says to use `zr run --emit
wasm`. `zr build` without `--target` then builds an
`aarch64-apple-darwin` binary, and says so. On a host that cannot link
a binary, `zr build` without `--emit` exits with status 3.

## Platform and minimum OS

A binary records the oldest OS that it loads on, and its
`RUBY_PLATFORM` names that OS, as ruby's names the platform that ruby
was built for:

| Target | Oldest OS | `RUBY_PLATFORM` |
|---|---|---|
| `aarch64-apple-darwin` | macOS 14 | `arm64-darwin23` (Darwin 23 is macOS 14) |
| `aarch64-linux-musl` | any aarch64 Linux kernel that musl supports | `aarch64-linux-musl` |
| `wasm32-wasi` | any WASI preview 1 engine | `wasm32-wasi` |

`Zr::Target::MIN_MACOS` holds the macOS version. zr's Mach-O linker and
`cc` (`-mmacosx-version-min`) write it.

## Differences between targets

| | darwin | linux-musl | wasi |
|---|---|---|---|
| Linker | zr's own (`Obj::MachO::Executable`) | `cc -static` | none: one module |
| `Fiber`, `Thread`, `Ractor` | yes | yes | no: a module has one stack; `Fiber.new` raises `FiberError` |
| `eval` of a string | yes, with the eval compiler | yes, with the eval compiler | yes, with the tree-walking interpreter |
| FFI (`ffi`, `fiddle`) | yes | no | no |
| Preemption | a timer thread | a timer thread | a count at each safe point |
| Expected output | `foo.rb.expected` | the same, or `foo.rb.linux.expected` | the same, or `foo.rb.wasi.expected` |

The program tests that a target is allowed to fail are in its
baseline, `test/baselines/<triple>.txt`.
See [How to test on another target](../how-to/test-on-another-target.md).

### What wasm cannot do

Two groups in the `wasm32-wasi` baseline are not work to do later:

- **Fibers, threads and ractors.** Each needs a second machine stack,
  and a WASI module has only one, which the engine keeps (see
  [Threads, fibers and ractors](../explanation/threads-fibers-and-ractors.md)).
  No call that the runtime can make creates another. The solution is
  the **stack-switching proposal**, which gives a module its own
  continuations. wasmtime does not include it, so `Fiber.new` raises
  `FiberError`, and `fiber_resume` and `threads_join` stay in the
  baseline until an engine includes it.
- **Processes and POSIX signals.** WASI has no `fork`, no `exec` and no
  `kill`, and no proposal adds them. `spawn` and `Signal.trap` stay in
  the baseline.

The other lines are work to do: the memory that some builds need, a
socket table that nobody has written, rubygems' reads of its own files
by absolute path, libm (the WASI layer defines only `frexp` and
`ldexp`), `chdir`, one form that the tree-walking interpreter does not
run, and `dlopen`, which wasm does not have.

A darwin or linux program that evals writes the machine code that it
compiles into itself. The engine fixes a module's code when it
instantiates the module, and WASI gives a guest no way to make a second
module. Thus a wasm program uses the same front end and the
tree-walking interpreter. See
[Eval in a compiled program](../explanation/eval-in-a-compiled-program.md)
for the forms that the interpreter refuses.

## Runtime layers

The portable runtime calls a fixed set of OS functions, which
`lib/zr/runtime/kernel/os.rb` lists. Each OS layer implements all of them:

| Directory | Contains |
|---|---|
| `lib/zr/runtime/kernel/os/<os>/` | the kernel's OS calls: errno, descriptors, stacks, POSIX signals, JIT mapping |
| `lib/zr/runtime/kernel/arch/<arch>/` | the machine context that a task switch saves |
| `lib/zr/runtime/core/os/<os>/` | the numbers that the OS gives the errno, IO, File and Process constants |
| `lib/zr/runtime/ext/os/<os>/` | extension tables (fcntl, etc, socket) and the description |

The table files come from the ruby of that OS (`zr-dev gen tables`).
