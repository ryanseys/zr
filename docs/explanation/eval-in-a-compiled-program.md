# Eval in a compiled program

Ruby can run a string of code while a program runs: `eval`,
`instance_eval` with a string, `Binding#eval`, and a `require` of a
file whose name the program computes. A compiler that turns Ruby into
machine code before the program runs must decide what to do with
this. This page explains zr's solution: eval support.

## Three possible solutions

A compiler for Ruby can:

1. refuse every program that can eval;
2. include an interpreter for evaluated code; or
3. include the compiler itself, and compile the string when it runs.

The first solution refuses too much. `pp`, `erb` and many other
libraries in ruby's standard library eval. The second solution gives
two implementations of Ruby, and two sets of results to keep equal to
ruby's. On a native target, zr uses the third: evaluated code goes
through the same compiler, the same runtime and the same tests as the
rest of the program. This is the **eval compiler**.

On wasm, the third solution is not possible. The engine fixes the code
of a module when it instantiates the module, and WASI gives a guest no
way to make a second module. Thus there is no place for the machine
code of the string. A WASI program uses the second solution: the
**tree-walking interpreter**. It costs as little as possible, because
the **front end is the same**: the same prism port, the same
`Hir.build`, the same desugaring and name resolution. Only the back
half is different: it walks the tree that the front end made. zr
refuses a form that the tree-walking interpreter does not support, with
a message that gives the form and the line.

`lib/zr/eval.rb` is the eval compiler, and `lib/zr/eval/interpreter.rb` is the
tree-walking interpreter. `Library::Roots.eval_file` selects one of them for
the target.

## Which programs include eval support

The HIR build decides, from the source, whether a program can reach
the compiler while it runs. A program includes eval support when it
contains:

- `eval`, or `instance_eval`, `class_eval` or `module_eval` with an
  argument;
- a `require`, `require_relative` or `load` of a file that zr cannot
  find at compile time;
- a change to `$LOAD_PATH` other than the addition of a literal
  directory;
- a `send` or a `method` that can reach one of these.

A program without these does not include eval support. Its binary is
smaller and starts faster.

## How the eval compiler runs

The compiler is Ruby, so zr can compile it like any other program. zr
builds eval support into its own object one time, and keeps it in the
cache (an `object` entry of the store). A program that evals links that object beside
the runtime.

The compiler loads only when the program evaluates its first string.
Many programs that can eval never do, and the load of the compiler
makes about a hundred thousand objects.

For each string, the eval compiler:

1. parses it with the prism port;
2. lowers it as one scope inside the locals of the calling scope, so
   that it can read and write them;
3. assembles it with the aarch64 backend; and
4. loads the machine code into the process with `Obj::JIT`, through the
   runtime's own calls to map and protect memory.

The string's calls into the runtime and the program are resolved by
name. zr's linker sorts the symbol table of the image by name
(`Obj::MachO::Executable`), so the kernel finds each name with a
binary search (`zr_os_symbol`, `lib/zr/runtime/kernel/os/darwin/jit.rb`). It
calls `dlsym` only for a libSystem name, or for all names in an image
that `ld` linked, whose table is not sorted.

The evaluated code must agree with the code around it about the
kernel's functions, layouts and symbol IDs. For this, the program
includes the kernel's description (`zr_description.rb`, which the
build writes into its cache from the kernel), and the symbol table of the
string starts from the program's own.

## How the compiler stays out of the program's sight

In ruby, the compiler is C. A program cannot change it, trace it or
see its objects. zr's eval compiler is Ruby that runs in the program's
own process, so zr keeps the program's state and the compiler's state
apart:

- **Globals.** Before a compile, `Zr::Eval.plainly` resets the
  separator globals (`$,`, `$;`, `$/`, `$\`) and `GC.stress`, and it
  puts them back after the compile.
- **Redefinitions.** The compiler's units compile like the core
  library: a send of a name that is not a protocol name (SEND_CORE)
  finds the core's own method, and an operator on two immediates
  compares natively whatever the program redefines.
- **Tracing.** A TracePoint of the program sees no event from a frame
  of the compiler, and the program's own hooks (`method_added`,
  `inherited` and the others) do not run for the compiler's classes.
- **Reflection.** A class that the compiler makes is concealed:
  `ObjectSpace` and `Class#subclasses` do not show it. A file that the
  compiler requires is not in `$LOADED_FEATURES`. A constant that it
  defines on Object and a method that it adds to a class of the program
  (for example, digest's `Object#Digest`) stay hidden. When the program
  requires the same file itself, the file's constants and methods
  become visible, and the file goes into `$LOADED_FEATURES`, as ruby
  would load it then.

One case is not isolated: a program that removes a core constant that
the compiler reads by name, such as `::Set`, stops the next eval.

## How the tree-walking interpreter runs

`ZR_EVAL=walk` builds a native program with the tree-walking
interpreter. The tests use it to check the interpreter against the
eval compiler: the same program, the same runtime, and two back halves
that must both agree with ruby.

The interpreter evaluates the HIR node by node. It calls the program
through the methods that any Ruby program uses: `__send__`,
`define_method`, `instance_variable_get`. For what only the runtime
knows, it uses `Zr::Eval::World` (`lib/zr/runtime/lib/zr/eval/world.rb`):
the lexical scope of a cref, the scopes of a Binding, and the constant,
class-variable and global tables. Each of these is in place of code
that the compiler writes inline.

While the interpreter runs, the runtime knows that the caller is the
program, not a file of eval support (`zr_walk_enter`). The program
cannot see the files of eval support. Without this, a constant that a
string defines on Object would be hidden as if a file of eval support
defined it.

The interpreter reads the frame that called eval through its Binding:
`$~` and `$_` are that frame's (a match in the string sets them there,
and a method that the string defines keeps its own), a `return` leaves
that frame's method as compiled eval code does (`zr_binding_return`),
and `super` outside a `def` of the string calls that method's super.

The tests run the interpreter on CRuby, over a `World` of plain Ruby
(`test/support/interpreter_world.rb`, `test/unit/eval_walk_test.rb`), so a
change to it is checked in a fraction of a second with no build.

The tree-walking interpreter refuses these forms, with a message that
gives the form:

- `using`, and a call under a refinement.
- `caller` and `caller_locations` written in the string.
- `defined?` of an Array or Hash literal.
- A `require` of a file that zr did not compile into the program. It
  needs a top-level address that the interpreter does not have.
- `RubyVM::InstructionSequence.compile`, which asks for code to run
  later.

`binding` in the string copies the string's own locals: a later write
in the string does not reach that Binding.

Backtraces give the interpreter's own files, not the line of the
string.

## Where the code is

The code of eval support is in five places. Some files go into the
program, and some run on the host that builds it.

| File | What it is | Where it runs |
|---|---|---|
| `lib/zr/eval.rb` | `Zr::Eval`, the eval compiler: the entry of eval support on a native target | in the program |
| `lib/zr/eval/interpreter.rb`, `lib/zr/eval/interpreter/` | the tree-walking interpreter: the entry of eval support on wasm, or with `ZR_EVAL=walk` | in the program; the tests also run the walk on ruby |
| `lib/zr/runtime/lib/zr/eval/` | what only the runtime can give an eval: the symbol table and `using` (`runtime.rb`), the string forms of `eval` over the compiler (`forms.rb`) or over the interpreter (`interpreter_forms.rb`), and the interpreter's world (`world.rb`) | in the program, as files of the runtime's own library |
| `lib/zr/eval_support.rb` | `Zr::EvalSupport`, which builds eval support once into its own object, with the metadata that a program needs | on the host |
| `lib/zr/cache/lowering/eval_support.rb` | the cache of each file's lowering in eval support, so an edit lowers one file again, not all of them | on the host |

`Library::Roots.eval_file` (`lib/zr/library/roots.rb`) chooses the
entry for the target.

## Limits

- A WASI module contains the whole front end, where a binary links a
  cached object. Thus a WASI program that evals is about 90 MB, and its
  build takes about three minutes.
- An engine compiles a module whole before it runs it. Thus the 90 MB
  module needs about 2.1 GB of the host's memory when wasmtime
  instantiates it (measured on `test/programs/cli/lang/eval/eval_in_a_binary.rb`).
  The program's own memory is a small part of this. `wasmtime compile`
  moves this cost out of the run.
- A binary with eval support contains the absolute paths of the gem's
  `lib/zr/runtime/ext`, `lib/zr/runtime/lib` and `vendor/ruby`. A computed
  `require` in such a binary works only while that version of the gem
  stays installed.
