# Glossary

The docs use one term for one concept. This page defines the terms.

**Baseline.** The file `test/baselines/<triple>.txt`: the program
tests that a target is allowed to fail, each with a reason. See
[How to test on another target](../how-to/test-on-another-target.md).

**Binary.** A native executable that zr builds, for
`aarch64-apple-darwin` or `aarch64-linux-musl`.

**Builtin.** A method that the runtime defines, from the core library
or the kernel. The program does not define it.

**Cache.** The directory where zr keeps what it builds once and uses
again: the runtime object, eval support, the prelinked images, the
compilation units. `tmp/cache` in a checkout; see `ZR_CACHE` in
[Environment variables](environment-variables.md). Not the same as an
inline cache.

**Cache entry.** One entry of an inline cache: a receiver class, a
method stamp, and the method that a send found for them.

**Cell.** A fixed-size block of the heap that contains one object: 32,
64, 128 or 256 bytes.

**Compilation unit.** Code that zr lowers and assembles as one part.
For a program, each source file is a compilation unit, and the cache
keeps its machine code. In the kernel, a compilation unit is
a group of files whose declarations see each other.

**Compiled compiler.** zr, compiled by zr: stage 1 of
[Bootstrapping](../explanation/bootstrapping.md). `zr-dev stage 2` and
`zr-dev compile --zr` build it to check and time the compiler. The `zr`
command does not use it; ruby runs zr.

**Core library.** `lib/zr/runtime/core/`: Ruby's core classes, written in
ordinary Ruby over the kernel.

**Cref.** The lexical scope that a method or a block runs in: where a
`def` goes, and where zr looks up constants.

**Description.** The kernel's signatures, effects, constants and struct
layouts, as text (`zr_description.rb`, which a build writes into the
cache from the kernel, in `store/description/`). A program
that evals includes the description in place of the kernel's sources.

**Digest.** A SHA-256 hash of all the inputs of a built file. zr gives
the digest to the name of each entry of the cache, for example
`store/object/ab/ab12….o` for the runtime object. A change to an input
makes a new digest, and thus a new build.

**Effects.** The regions of memory that a call can write, one bit for
each region: the gate word, the stamps, the task, the heap cells, the
malloc payloads, the other statics, and the volatile words that a timer
or a POSIX signal writes (`IR::Effects`). The effects of a kernel def
are the union over its body and the defs it calls. A pass keeps a
loaded value across a call only if the call cannot write the value's
region.

**Env.** The cell that contains the locals that a block captures.

**Eval compiler.** The part of eval support on a native target: zr's
own compiler, linked into the program. It compiles each string to
machine code while the program runs (`lib/zr/eval.rb`).

**Eval support.** What zr links into a program that can call `eval`:
the front end (the prism port and the HIR build) and a back end, which
is the eval compiler on a native target and the tree-walking
interpreter on wasm (`Zr::EvalSupport`). See
[Eval in a compiled program](../explanation/eval-in-a-compiled-program.md).

**Extensions.** `lib/zr/runtime/ext/`: the native halves of extension gems,
written in ordinary Ruby.

**Frame record.** The part of a function's machine frame that contains
its Ruby state: self, the line, and every Value that the function
keeps. The collector reads it. See [Runtime layouts](runtime-layouts.md).

**Gap.** An example that zr cannot pass yet. It stays in its place,
with `skip "<what it needs>"`.

**Gate.** One bit of the gate word. A gate is clear while a fast path
is correct. When a program redefines the method that the fast path
replaces (for example `Integer#+`), the kernel sets the gate, and the
fast path is off for the rest of the run. The gate word is in a
register (`x28`; a global on wasm).

**HIR.** The compiler's tree form of a program: prism's tree, desugared,
with names resolved.

**Home.** The frame that a `break` or a `return` goes back to, given
by its address and serial number.

**Host.** The machine that runs zr.

**Inline cache.** The cache entries that a send site owns: four
`CallCache` entries. The site tests the first entry itself. See
[Method dispatch and unwinding](../explanation/method-dispatch-and-unwinding.md).

**IR.** The compiler's control-flow graph in SSA form, with block
parameters. Every lowering writes it, and every backend reads it.

**Kernel.** `lib/zr/runtime/kernel/`: the lowest layer of the runtime, in
typed Ruby. Each file is one `module Zr::Kern`.

**Library roots.** The directories that a program's `require` searches,
in order: zr's own code first, then the port gems, then ruby's own
library and the bundled gems (`Library::Roots.stdlib`,
`lib/zr/library/roots.rb`).

**Lowering.** The change of the program from one form to a lower one:
HIR to IR, or the kernel's typed Ruby to IR.

**Machine dialect.** The old form of the kernel: top-level statements,
`machine def` and `Machine.import`. `tool/kern_rewrite.rb` changed it
to typed Ruby. See **Typed Ruby**.

**Method stamp.** A global word that every change to a method table or
an ancestor chain changes. The collector also changes it when it frees
a class. A cache entry is correct only while its method stamp is the
same as the global one.

**Object file.** The output of `zr build --emit obj`: Mach-O, or ELF for
`aarch64-linux-musl`. It contains only the program's own code.

**OS layer.** The parts of the runtime that each operating system does
in its own way, in `os/<os>/` directories.

**Pending unwind.** A `raise`, `break`, `return` or `throw` that is in
progress. While one is pending, each function returns undef to its
caller, until a frame takes it.

**Poll word.** A word that a timer, a POSIX signal or a finalizer sets.
Compiled code tests it at safe points to switch threads.

**POSIX signal.** A signal of the operating system, such as `SIGINT`.
Not a pending unwind.

**Prelinked image.** The runtime object, read back, put at fixed
addresses, with its relocations applied (`store/image/` in the
cache). Every binary starts with the runtime at those addresses, so a
link relocates only the program.

**Primitive.** `Primitive.zr_name(...)` in the core library: a direct
call of a kernel def, with no dispatch.

**Program test.** A plain `.rb` file in `test/programs/`, with ruby's
output in files beside it (`foo.rb.expected` and others). zr builds it
and compares the binary's output with ruby's. `zr-dev expect` writes
the expected files. See [Program tests](program-tests.md).

**Recording.** The files beside a benchmark that contain ruby's
output: `.out` (stdout), `.err` (stderr), `.status` (an exit status
that is not 0) and `.signal`. `zr-dev record` writes them. See
[Benchmark recordings](test-format.md).

**Reference ruby.** ruby 4.0.7 with only the reference gems
(`tmp/reference/gems`): the only source of expected outputs
(`Harness::Reference`).

**Refusal.** zr does not support a form, so it does not compile it. It
prints the form and the line, and exits with status 3.

**Run directory.** The new temporary directory that one run of a
program test gets, with a copy of the program and its files. ruby and
the binary run in it in the same way. See
[Program tests](program-tests.md#the-run-directory).

**Runtime.** The code that zr compiles into every program: the kernel,
the core library and the extensions.

**Site.** A place in compiled code that does a send, reads a constant
or reads an instance variable, and owns the cache entries for it.

**Skeleton.** The bytes that every binary linked beside one prelinked
image starts with: the header page and the runtime's `__TEXT`
(`skeleton-<digest>.bin` in the cache). A link clones the skeleton and
writes only the rest.

**Snapshot.** A committed file that a unit test compares its output
with: the HIR dumps, the disassembly listing, the descriptions, the
libSystem list. `ZR_BLESS=1` writes it again.

**Stage 1, stage 2.** The compiler that ruby builds, and the compiler
that stage 1 builds. See [Bootstrapping](../explanation/bootstrapping.md).

**Target.** What zr builds for: `aarch64-apple-darwin`,
`aarch64-linux-musl` or `wasm32-wasi`. See [Targets](targets.md).

**Task.** A fiber, with its own machine stack. Threads and ractors run
on tasks.

**Tier.** One of the two groups of tests: unit (`test/unit`) and
programs (`test/programs`). See
[How the tests run](../explanation/how-the-tests-run.md).

**Tree-walking interpreter.** The part of eval support on wasm. It
runs the HIR of a string node by node (`lib/zr/eval/walk.rb`).
`ZR_EVAL=walk` uses it on a native target too.

**Typed Ruby.** The language of the kernel: plain Ruby syntax in one
`module Zr::Kern` for each file, with a `#:` comment of machine types above
each `def`. See [The kernel's typed Ruby](machine-dialect.md).

**Undef.** The Value `0x34`. A function returns it when an unwind is
pending.

**Unit test.** A minitest file in `test/unit/`.

**WASI module.** The output of `zr build --emit wasm`: a WebAssembly
module for `wasm32-wasi`.

**Word.** 8 bytes, or 64 bits. The `Word` type of the kernel's typed Ruby.

**zr.** The project, the gem and the command. The runtime's symbols
are `zr_*`, and the environment variables are `ZR_*`.
