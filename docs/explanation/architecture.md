# Architecture

This page follows a program from its source to a binary, and explains
why the compiler has the layers it has.

```
app.rb ─┐
rt/**   ├─ prism ─► HIR ─► IR ─► passes ─┬─► aarch64 backend ─► Obj ─┬─► Mach-O executable writer ─► binary
        │                                │                          ├─► ELF object ─► cc ─► Linux binary
        │                                │                          └─► JIT loader (eval, in process)
        │                                ├─► wasm emitter ─► WASI module
        │                                └─► IR interpreter (a second opinion, not a road)
```

Every box is Ruby. The only tools outside ze0 are `cc`, to link a
Linux binary, and wasmtime, to run modules.

## Parsing: prism

ze0 parses with prism, the parser ruby itself uses. Using ruby's own
parser is the only practical way to accept exactly the programs ruby
accepts, with the same syntax errors. prism's C is ported to Ruby
(`rt/ext/prism/ruby`), so the compiler parses with the same code on the
host and inside a compiled program. See
[Why ze0 has no C](why-ze0-has-no-c.md).

## The HIR: the language, made plain

`lib/ze0/hir/` turns prism's tree into the HIR, a tree with one node
class for each kind of construct. It is desugared and name-resolved:
operator assignment, safe navigation, multiple assignment,
interpolation, `case`/`when` and `case`/`in`, and the whole parameter
surface become a small set of nodes. The HIR build also follows
`require`s, so a program and every file it loads are one unit.

The HIR exists because the step from Ruby to machine operations is too
large for one pass. Compilers with more than one target keep a layer
that speaks the language above a layer that speaks the machine: rustc
has HIR over MIR, and ZJIT has an SSA HIR over a LIR. The HIR is where
a form that ze0 cannot compile is refused, by name, at its line.

## The IR: one form for every backend

`lib/ze0/zr/` lowers the HIR to the IR (`lib/ze0/ir/`), a control-flow
graph in SSA form with block parameters. It has 47 opcodes and four
types: `i8`, `i32`, `i64` and `f64`. The kernel dialect
(`lib/ze0/machine/`) lowers to the same IR. So every backend reads one
form, whether the code came from a program or from the runtime.

The IR has two firm limits. A function takes at most eight parameters,
and a call passes at most eight arguments, so no backend needs a stack
argument path. And no call is variadic.

Before a backend sees a function, `IR::Passes` runs the same pipeline
for every emitter: small leaf functions inline into their callers, then
constant folding, store-to-load forwarding, the kernel's guard words
(the gates, the stamps, the task pointer) promoted to values that a
call or a store the pass cannot place reloads, branch chains, block
merging and dead code removal. `IR::Verify` then checks the result.

## The backends

The **aarch64 backend** (`lib/ze0/backend/aarch64/`) selects
instructions nearly one to one from the IR, and its own assembler
encodes them. A linear-scan allocator gives values registers from two
pools: callee-saved registers for values that live across a call, and
caller-saved registers for the rest. The `aarch64` gem, generated from
the ARM specification, checks every encoding in the tests.

The **wasm emitter** (`lib/ze0/backend/wasm/`) writes one WASI module.
Control flow is a loop around a `br_table` over the function's blocks,
and stack slots live in a shadow stack in linear memory.

**`IR::Interp`** runs IR directly. It is not a way to run programs; it
is a second answer, so a miscompile shows as a disagreement.

## Objects and linking

The backend writes an `Obj`: functions, data, relocations and symbols,
with no file format. Three writers read it:

- `Obj::MachO::Executable` is ze0's macOS linker. It links a program
  beside a `Prelink`, and writes a complete, signed executable that
  imports only from libSystem.
- The Mach-O and ELF object writers write objects: the cached runtime,
  `--emit obj`, and the ELF objects that `cc` links for Linux.
- `Obj::JIT` loads code into the running process, for `eval`.

The runtime is large, so ze0 compiles it once for each version of its
sources and keeps the object in the cache (`rt-<digest>.o`). A program's
build lowers only the program, and ze0's linker links it beside the
cached runtime.
A cold build assembles the runtime in parallel worker processes, and
the result is the same bytes for any number of workers.

The runtime is also linked once. `Obj::MachO::Prelink` reads the
runtime's object back (and the eval road's, for a program that evals),
places it at fixed addresses, applies its relocations, and keeps the
result in the cache (`prelink-<digest>.bin`). Every binary puts the
runtime at those same addresses. The program's code goes in a
`__PROGRAM` segment after the runtime's `__TEXT`, within a branch's
reach of it. The program's data goes in a `__DATA_PROGRAM` segment after
the runtime's `__DATA`. The runtime's `__DATA_CONST` starts a fixed
distance after `__TEXT`, so the program's size moves no runtime address.
A link relocates only the program. It writes the runtime's bytes and
page hashes as they were kept, and writes again only the runtime's
slots for names that the program or libSystem defines.

## The runtime

The runtime is compiled into every program. It has three layers, all
Ruby: the kernel, the core library and the extensions. See
[The runtime](the-runtime.md).
