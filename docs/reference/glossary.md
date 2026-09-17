# Glossary

**Builtin.** A method the runtime defines, from the core library or the
kernel, as opposed to a method the program defines.

**Case.** One corpus program: a `.rb` file with ruby's answer under
`__END__`. See [The test format](test-format.md).

**Cell.** A fixed-size block of the heap that holds one object: 32, 64,
128 or 256 bytes.

**Check.** A Minitest file in `test/unit/`, run by `bin/ze0 check`.

**Core library.** `rt/core/`: Ruby's core classes, written in ordinary
Ruby over the kernel.

**Corpus.** The directories of cases under `test/` that ze0 is held to.

**Cref.** The lexical scope a method or block runs in: where a `def`
lands and where constants are looked up.

**Description.** The kernel's signatures, constants and struct layouts
as text (`rt/ext/os/<os>/zr_description.rb`). A program that evals
carries it instead of the kernel's sources.

**Diverged.** A case whose binary answered something other than ruby's
recording.

**Env.** The cell that holds the locals a block captures.

**Frame record.** The block of a function's machine frame that holds
its Ruby state: self, the line, and every Value it holds. The collector
reads it. See [Runtime layouts](runtime-layouts.md).

**Gap.** A case ze0 does not answer yet, kept in `test/gaps/`.

**HIR.** The compiler's tree form of a program: prism's tree, desugared
and name-resolved.

**Home.** The frame a `break` or a `return` goes back to, named by its
address and serial.

**IR.** The compiler's CFG in SSA form, with block parameters. Every
lowering writes it and every backend reads it.

**Kernel.** `rt/kernel/`: the runtime's lowest layer, in the kernel
dialect.

**Kernel dialect.** Ruby syntax with machine semantics, for the kernel.
See [The kernel dialect](kernel-dialect.md).

**Lowering.** Turning one form of the program into a lower one: HIR to
IR, or the kernel dialect to IR.

**OS layer.** The part of the runtime that each operating system
implements in its own way, under `os/<os>/` directories.

**Oracle.** The source of the right answer. For ze0, that is ruby 4.0.6
and nothing else.

**Poll word.** A word that a timer, a signal or a finalizer sets, and
that compiled code tests at safe points to switch threads.

**Primitive.** `Primitive.zr_name(...)` in the core library: a direct
call of a kernel def.

**Refusal.** ze0 declines to compile a form it cannot compile correctly.
It names the form and its line, and exits with status 3.

**Road.** A path from source to output: the native road, the wasm road,
the eval road.

**Signal.** A pending raise, `break`, `return` or `throw`. A function
answers `undef` while one is pending.

**Stage 1, stage 2.** The compiler built by ruby, and the compiler built
by stage 1. See [Bootstrapping](../explanation/bootstrapping.md).

**Task.** A fiber, with its own machine stack. Threads and ractors run
on tasks.

**Undef.** The Value `0x34`. A function answers it to say a signal is
pending.

**zr.** The runtime's name: its symbols are `zr_*`, and its environment
variables `ZR_*`.
