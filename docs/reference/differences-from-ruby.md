# Differences from ruby

ze0 gives ruby 4.0.6's answer or it refuses by name
([the contract](../explanation/the-contract.md)). This page lists each
place where ze0 does not give ruby's answer on purpose. There are two
kinds:

- **A refusal.** The answer needs something that a compiled program does
  not have, such as YARV bytecode. ze0 raises `NotImplementedError` with
  a message that names the method, and it does not give a wrong answer.
- **A ruby bug.** ruby 4.0.6 itself goes wrong, for example it hangs.
  ze0 gives the answer that ruby's documentation gives, and a note at
  the code names the difference.

Each row names the spec that holds the behavior, where there is one.

## Refusals

| What | ze0 | ruby 4.0.6 |
|---|---|---|
| `RubyVM::InstructionSequence#disasm`, `#disassemble`, `#to_a` | `NotImplementedError`: ze0 compiles to machine code, and it has no YARV bytecode to show | the bytecode |
| `RubyVM::InstructionSequence#to_binary` of a compiled string | `NotImplementedError`, for the same reason | the bytecode as a String |
| `#each_child` and `#trace_points` of a block's or a method's iseq | `NotImplementedError`: the binary does not keep the source of a block | the child iseqs, and the events |
| `Coverage.setup(eval: true)`, then an eval while coverage runs | `NotImplementedError` at the eval: the string is not a file that the build read, so no line of it can be measured. A program that asks for eval coverage and never evals gets ruby's answer. | the eval's lines in the result |
| The message of a `SyntaxError` from `RubyVM::AbstractSyntaxTree.parse` | prism's message: ze0 parses with prism alone | the message of ruby's older parser, parse.y |
| `GC::Profiler.raw_data` and `GC::Profiler.result` | an empty list and an empty report: the collector keeps no rows for each run | a row for each run |
| A method reached only through a name the program builds at run time, such as `send("ev" + "al", ...)` | `NotImplementedError` when the method needs a part of the runtime that the program did not ask for (the compiler, the normalization tables, pp.rb) | the method's answer |

The spec `core/rubyvm/rubyvm_test.rb` "an InstructionSequence answers
eval, to_binary and each_child as ruby does" holds the parts of
`InstructionSequence` that ze0 answers.

## Ruby bugs

| What | ze0 | ruby 4.0.6 |
|---|---|---|
| A second deadlock after a deadlock that the program rescued (a thread waits on a Queue that no thread feeds, the program rescues the `fatal`, then the main thread waits again) | raises `fatal` "No live threads left. Deadlock?" again. After some mixes of queues, mutexes and condition variables it aborts with "a terminated fiber ran again" instead, which is a ze0 bug still open. | hangs |
