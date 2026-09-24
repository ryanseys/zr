# Differences from ruby

zr gives ruby 4.0.6's answer or it refuses by name
([the contract](../explanation/the-contract.md)). This page lists each
place where zr does not give ruby's answer on purpose. There are two
kinds:

- **A refusal.** The answer needs something that a compiled program does
  not have, such as YARV bytecode. zr raises `NotImplementedError` with
  a message that names the method, and it does not give a wrong answer.
- **A ruby bug.** ruby 4.0.6 itself goes wrong, for example it hangs.
  zr gives the answer that ruby's documentation gives, and a note at
  the code names the difference.

Each row names the spec that holds the behavior, where there is one.

## Refusals

| What | zr | ruby 4.0.6 |
|---|---|---|
| `RubyVM::InstructionSequence#disasm`, `#disassemble`, `#to_a` | `NotImplementedError`: zr compiles to machine code, and it has no YARV bytecode to show | the bytecode |
| `RubyVM::InstructionSequence#to_binary` of a compiled string | `NotImplementedError`, for the same reason | the bytecode as a String |
| `#each_child` and `#trace_points` of a block's or a method's iseq | `NotImplementedError`: the binary does not keep the source of a block | the child iseqs, and the events |
| `Coverage.setup(eval: true)`, then an eval while coverage runs | `NotImplementedError` at the eval: the string is not a file that the build read, so no line of it can be measured. A program that asks for eval coverage and never evals gets ruby's answer. | the eval's lines in the result |
| The message of a `SyntaxError` from `RubyVM::AbstractSyntaxTree.parse` | prism's message: zr parses with prism alone | the message of ruby's older parser, parse.y |
| `GC::Profiler.raw_data` and `GC::Profiler.result` | an empty list and an empty report: the collector keeps no rows for each run | a row for each run |
| A method reached only through a name the program builds at run time, such as `send("ev" + "al", ...)` | `NotImplementedError` when the method needs a part of the runtime that the program did not ask for (the compiler, the normalization tables, pp.rb) | the method's answer |

The spec `core/rubyvm/rubyvm_test.rb` "an InstructionSequence answers
eval, to_binary and each_child as ruby does" holds the parts of
`InstructionSequence` that zr answers.

## The locale

A program's locale is UTF-8 wherever it runs: `Encoding.locale_charmap`
answers `"UTF-8"`, and the main file's `__FILE__`, `$0` and `__dir__`
are UTF-8 strings. ruby takes the locale from `LANG` and `LC_ALL` as the
program starts, so under `LANG=C` those three are US-ASCII there. A
build does not read its own locale either: two builds under two locales
write the same bytes (`rake repro`).

## Ruby bugs

| What | zr | ruby 4.0.6 |
|---|---|---|
| A second deadlock after a deadlock that the program rescued (a thread waits on a Queue that no thread feeds, the program rescues the `fatal`, then the main thread waits again) | raises `fatal` "No live threads left. Deadlock?" again | hangs |
| `String#grapheme_clusters` of a UTF-16 string with a lone lead surrogate before other characters, such as `"a\x00\x00\xD8b\x00"` in UTF-16LE | each character stays whole: `["a\x00", "\x00\xD8", "b\x00"]` | the engine splits the code units: `["a\x00", "\x00", "\xD8b"]` |
