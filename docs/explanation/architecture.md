# Architecture

This page follows a program from its source to a binary, and explains
why the compiler has its layers.

```
app.rb ─────┐
runtime/**  ├─ prism ─► HIR ─► IR ─► passes ─┬─► aarch64 backend ─► Obj ─┬─► Mach-O executable writer ─► binary
            │                                │                          ├─► ELF object ─► cc ─► Linux binary
            │                                │                          └─► JIT loader (eval, in process)
            │                                ├─► wasm emitter ─► WASI module
            │                                └─► IR interpreter (a second opinion for the tests)
```

Every box is Ruby. The only tools outside zr are `cc`, to link a Linux
binary, and wasmtime, to run modules.

## Parsing: prism

zr parses with prism, the parser that ruby uses. Only ruby's own parser
accepts exactly the programs that ruby accepts, with the same syntax
errors. zr has a Ruby port of prism's C (`runtime/ext/prism/ruby`), so
the compiler parses with the same code on the host and inside a
compiled program. See [Why zr has no C](why-zr-has-no-c.md).

## The HIR: the language, made plain

`lib/zr/hir/` changes prism's tree into the HIR, a tree with one node
class for each kind of construct. The HIR is desugared, with names
resolved: operator assignment, safe navigation, multiple assignment,
interpolation, `case`/`when` and `case`/`in`, and all the parameter
forms become a small set of nodes. The HIR build also follows
`require`s, so a program and every file that it loads are one program.

The HIR exists because the step from Ruby to machine operations is too
large for one pass. Compilers with more than one target keep a layer
for the language above a layer for the machine: ZJIT has an SSA HIR
over a LIR. zr refuses a form that it does not
support in the HIR, with a message that gives the form and the line.

## The IR: one form for every backend

`Zr::Lower` (`lib/zr/lower/`) lowers the HIR to the IR (`lib/zr/ir/`), a
control-flow graph in SSA form with block parameters. The IR has 54
opcodes and four types: `i8`, `i32`, `i64` and `f64`. The machine
dialect (`lib/zr/machine/`) lowers to the same IR. Thus every backend
reads one form, from a program or from the runtime.

The IR has two fixed limits. A function has at most eight parameters,
and a call has at most eight arguments, so no backend needs to pass
arguments on the stack. No call is variadic.

Before a backend gets a function, `IR::Passes` runs the same passes for
every emitter: small leaf functions are inlined into their callers,
then constant folding, store-to-load forwarding, value numbering over
the dominator tree (a load counts, and is kept across what cannot
write its region), loop-invariant code motion to a preheader, branch
chains, block merging and dead code removal. `IR::Verify` then checks
the result.

The kernel's gate word is not loaded from memory. It is in a register
of its own (`x28`; a global on wasm). The `gates` opcode reads it, the
defs that set a gate write it, and code that foreign code enters loads
it from its static.

## The backends

The **aarch64 backend** (`lib/zr/backend/aarch64/`) selects
instructions almost one to one from the IR, and its own assembler
encodes them. A linear-scan allocator gives values registers from two
groups: callee-saved registers for values that live across a call, and
caller-saved registers for the others. The tests check every encoding
against the `aarch64` gem, which is generated from the ARM
specification.

The **wasm emitter** (`lib/zr/backend/wasm/`) writes one WASI module.
Control flow is a loop around a `br_table` over the function's blocks,
and stack slots are in a shadow stack in linear memory.

**`IR::Interp`** runs IR directly. It is not a way to run programs. It
gives a second result, so a miscompile shows as a difference.

## Objects and linking

The backend writes an `Obj`: functions, data, relocations and symbols,
with no file format. Three writers read it:

- `Obj::MachO::Executable` is zr's macOS linker. It links a program
  beside a prelinked image, and writes a complete, signed executable
  that imports only from libSystem.
- The Mach-O and ELF object writers write object files: the cached
  runtime, `--emit obj`, and the ELF objects that `cc` links for Linux.
- `Obj::JIT` loads code into the running process, for the eval
  compiler.

The runtime is large, so zr compiles it one time for each version of
its sources and keeps the object in the cache (`runtime-<digest>.o`).
The build of a program lowers only the program, and zr's linker links
it beside the cached runtime. A cold build assembles the runtime in
parallel worker processes. The result is the same bytes for any number
of workers.

zr also links the runtime one time. `Obj::MachO::Prelink` reads the
runtime object back (and eval support, for a program that evals), puts
it at fixed addresses, applies its relocations, and keeps the result
in the cache as the prelinked image (`prelink-<digest>.bin`). Every
binary has the runtime at those addresses:

- The program's code is in a `__PROGRAM` segment after the runtime's
  `__TEXT`, where a branch can reach it.
- The program's data is in a `__DATA_PROGRAM` segment after the
  runtime's `__DATA`.
- The runtime's `__DATA_CONST` starts at a fixed distance after
  `__TEXT`, so the size of the program changes no runtime address.

A link relocates only the program. It writes the runtime's bytes and
page hashes as the image has them, and writes again only the runtime's
slots for names that the program or libSystem defines. The skeleton
(`skeleton-<digest>.bin`) contains the bytes that every such binary
starts with, and a link clones it where the file system can.

## The runtime

zr compiles the runtime into every program. It has three layers, all
Ruby: the kernel, the core library and the extensions. See
[The runtime](the-runtime.md).
