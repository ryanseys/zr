# Eval in a compiled program

Ruby can run a string of code while a program runs: `eval`,
`instance_eval` with a string, `Binding#eval`, and a `require` of a
file whose name is computed. A compiler that turns Ruby into machine
code ahead of time has to decide what to do about that. This page
explains zr's answer.

## Three answers, and the one zr takes

A compiler for Ruby can:

1. refuse every program that can eval;
2. include an interpreter for evaluated code; or
3. include the compiler itself, and compile the string when it runs.

The first answer refuses too much. `pp`, `erb` and many other libraries
in ruby's standard library eval somewhere. The second answer
gives two implementations of Ruby, and two sets of answers to keep
equal to ruby's. zr takes the third: evaluated code goes through the
same compiler, the same runtime, and the same checks as the rest of the
program.

On wasm the third answer is not available. A module's code is fixed
when the engine instantiates it, and WASI hands a guest no way to make
a second module, so there is nowhere to put what the compiler emits.
A program there takes the second answer instead, and pays for it as
little as it can: the **front end is the same one** -- the same prism
port, the same `Hir.build`, the same desugaring and name resolution --
and only the back half is a second implementation, a walk of the tree
the front end already built. What the walk does not carry it refuses
by name, at its line, rather than guessing. The two roads are
`lib/zr/eval.rb` and `lib/zr/eval/walk.rb`, and
`Hir::Build.eval_road_file` picks between them from the target.

## Which programs carry the compiler

The HIR build decides, from the source, whether a program can reach the
compiler at run time. A program carries it when it names:

- `eval`, or `instance_eval`, `class_eval` or `module_eval` with an
  argument;
- a `require`, `require_relative` or `load` whose file it cannot find
  as it compiles;
- a change to `$LOAD_PATH` other than a literal directory added;
- a `send` or a `method` that can reach one of these.

A program that does none of these carries nothing extra, and its binary
is smaller and starts faster.

## How an eval runs

The compiler is Ruby, so zr can compile it like any other program.
It builds the compiler into an object of its own once, and keeps it in
the cache (`road-<digest>.o`). A program that evals links that object
beside the runtime.

The compiler loads only when the program evaluates its first string.
Many programs that could eval never do, and loading the compiler makes
about a hundred thousand objects.

For each string, the carried compiler:

1. parses it with the prism port;
2. lowers it, one scope inside the locals of the asking scope, so it
   can read and write them;
3. assembles it with the aarch64 backend; and
4. loads the machine code into the process with `Obj::JIT`, over the
   runtime's own calls to map and protect memory. The snippet's calls
   into the runtime and the program are resolved by name: the image's
   own symbol table is sorted by name (`Obj::MachO::Executable`), so the
   kernel finds each one by a binary search of it (`zr_os_symbol`,
   runtime/kernel/os/darwin/jit.rb), and asks dlsym only for a name of
   libSystem's -- or for everything, in an image `ld` linked, whose
   table is in no order and whose exports trie holds every name.

An eval must agree with the code around it about the kernel's
functions, layouts and symbol ids. The program carries the kernel's
*description* for this (`runtime/ext/os/<os>/zr_description.rb`), and the
eval's symbol table starts from the one the program runs on.

## The walking road

`ZR_EVAL=walk` builds a native program with the walk, which is how the
walk is held to the compiling road's own answers: the same program, the
same runtime, and two back halves that must agree with ruby.

The walk evaluates HIR node by node and reaches the program through the
calls any Ruby program makes -- `__send__`, `define_method`,
`instance_variable_get`. What only the runtime can answer it asks
through `Zr::Eval::World` (`runtime/ext/zr/eval/walking.rb`): the lexical
scope a cref stands for, the scopes a Binding names, and the constant,
class-variable and global tables, each one standing for something the
compiler emits inline.

While it walks, the runtime is told that what asks is the program and
not the road's own file (`zr_walk_enter`). The road's files load out of
the program's sight, and without that a constant a string defines on
Object would be concealed as a hidden file's own.

What it does not carry, and refuses by name:

- `$~`, `$_`, `$&` and the numbered groups. They are registers of the
  frame that last matched, and the walk has no frame of its own to keep
  them in.
- `return` from an eval inside a method: the walk cannot unwind the
  compiled frame that called it.
- `super` written at the top of an eval rather than inside a `def` the
  eval itself holds.
- `using`, and a call written under a refinement.
- A `require` of a file the program was not compiled with, which wants
  a toplevel address the walk has none of.
- `RubyVM::InstructionSequence.compile`, which asks for code to run
  later.

Backtraces name the walk's own files rather than the string's line.

## Limits

- A WASI module holds the whole front end where a binary holds a
  cached object, so a wasm program that evals is about 90 MB and takes
  about three minutes to build.
- An engine compiles a module whole before it runs a line of it, so
  that 90 MB costs about 2.1 GB of the host's memory at instantiation
  -- measured on `e2e/lang/eval/eval_in_a_binary.rb` under wasmtime.
  The program's own memory is a fraction of it. `wasmtime compile`
  ahead of time moves the cost out of the run.
- A binary that carries the compiler names the absolute paths of the
  gem's `runtime/ext` and `vendor/ext/*/lib`, and of the library tree it was
  built against. A computed `require` in such a binary works only while
  that version of the gem, and its pinned gems, stay installed.
