# Eval in a compiled program

Ruby can run a string of code while a program runs: `eval`,
`instance_eval` with a string, `Binding#eval`, and a `require` of a
file whose name is computed. A compiler that turns Ruby into machine
code ahead of time has to decide what to do about that. This page
explains ze0's answer.

## Three answers, and the one ze0 takes

A compiler for Ruby can:

1. refuse every program that can eval;
2. include an interpreter for evaluated code; or
3. include the compiler itself, and compile the string when it runs.

The first answer refuses too much. `pp`, `erb` and many other libraries
in ruby's standard library eval somewhere. The second answer
gives two implementations of Ruby, and two sets of answers to keep
equal to ruby's. ze0 takes the third: evaluated code goes through the
same compiler, the same runtime, and the same checks as the rest of the
program.

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

The compiler is Ruby, so ze0 can compile it like any other program.
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
   runtime's own calls to map and protect memory.

An eval must agree with the code around it about the kernel's
functions, layouts and symbol ids. The program carries the kernel's
*description* for this (`rt/ext/os/<os>/zr_description.rb`), and the
eval's symbol table starts from the one the program runs on.

## Limits

- A static Linux binary and a WASI module cannot load code, so programs
  that eval work only on macOS.
- A binary that carries the compiler names the absolute paths of the
  gem's `rt/ext`, `vendor/lib` and `vendor/ext/*/lib`. A computed
  `require` in such a binary works only while that version of the gem
  stays installed.
