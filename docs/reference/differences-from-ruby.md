# Differences from ruby

zr gives ruby 4.0.6's output, or it refuses
([the contract](../explanation/the-contract.md)). This page lists each
place where zr does not give ruby's output on purpose. There are two
kinds:

- **A refusal.** The result needs something that a compiled program
  does not have, such as YARV bytecode. zr raises `NotImplementedError`
  with a message that gives the method. It does not give a wrong
  result.
- **A ruby bug.** ruby 4.0.6 itself goes wrong, for example it stops
  responding. zr gives the result that ruby's documentation gives, and
  a comment at the code tells the difference.

Each row gives the spec that tests the behavior, where there is one.

## Refusals

| What | zr | ruby 4.0.6 |
|---|---|---|
| `RubyVM::InstructionSequence#disasm`, `#disassemble`, `#to_a` | `NotImplementedError`: zr compiles to machine code, and has no YARV bytecode to show | the bytecode |
| `RubyVM::InstructionSequence#to_binary` of a compiled string | `NotImplementedError`, for the same reason | the bytecode as a String |
| `#each_child` and `#trace_points` of the iseq of a block or a method | `NotImplementedError`: the binary does not keep the source of a block | the child iseqs, and the events |
| `Coverage.setup(eval: true)`, then an eval while coverage runs | `NotImplementedError` at the eval: the string is not a file that the build read, so zr cannot measure its lines. A program that asks for eval coverage and never evals gets ruby's result. | the lines of the eval in the result |
| The message of a `SyntaxError` from `RubyVM::AbstractSyntaxTree.parse` | prism's message: zr parses only with prism | the message of ruby's older parser, parse.y |
| `GC::Profiler.raw_data` and `GC::Profiler.result` | an empty list and an empty report: the collector keeps no data for each run | data for each run |
| A method that the program reaches only through a name that it builds at run time, such as `send("ev" + "al", ...)` | `NotImplementedError` when the method needs a part of the runtime that the program did not ask for (the compiler, the normalization tables, pp.rb) | the method's result |

The spec `core/rubyvm/rubyvm_test.rb` "an InstructionSequence answers
eval, to_binary and each_child as ruby does" tests the parts of
`InstructionSequence` that zr supports.

## The locale

A program's locale is UTF-8 on every host: `Encoding.locale_charmap`
returns `"UTF-8"`, and the main file's `__FILE__`, `$0` and `__dir__`
are UTF-8 strings. ruby gets the locale from `LANG` and `LC_ALL` when
the program starts, so under `LANG=C` these three are US-ASCII in
ruby. A build does not read its own locale either: two builds under two
locales write the same bytes (`zr-dev repro`).

## Ruby bugs

| What | zr | ruby 4.0.6 |
|---|---|---|
| A second deadlock after a deadlock that the program rescued (a thread waits on a Queue that no thread feeds, the program rescues the `fatal`, then the main thread waits again) | raises `fatal` "No live threads left. Deadlock?" again | stops responding |
| `String#grapheme_clusters` of a UTF-16 string with a lone lead surrogate before other characters, such as `"a\x00\x00\xD8b\x00"` in UTF-16LE | keeps each character whole: `["a\x00", "\x00\xD8", "b\x00"]` | splits the code units: `["a\x00", "\x00", "\xD8b"]` |
