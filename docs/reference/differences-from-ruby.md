# Differences from ruby

zr gives ruby 4.0.7's output, or it refuses
([the contract](../explanation/the-contract.md)). This page lists each
place where zr does not give ruby's output on purpose. There are three
kinds:

- **A refusal.** The result needs something that a compiled program
  does not have, such as YARV bytecode. zr raises `NotImplementedError`
  with a message that gives the method. It does not give a wrong
  result.
- **A ruby bug.** ruby 4.0.7 itself goes wrong, for example it stops
  responding. zr gives the result that ruby's documentation gives, and
  a comment at the code tells the difference.
- **A detail that zr does not copy.** The result comes from how CRuby
  keeps its tables or builds its extensions, and a program cannot
  depend on it portably. zr gives a result that is correct, but not
  the same bytes.

Each row gives the spec that tests the behavior, where there is one.

## Refusals

| What | zr | ruby 4.0.7 |
|---|---|---|
| `RubyVM::InstructionSequence#disasm`, `#disassemble`, `#to_a` | `NotImplementedError`: zr compiles to machine code, and has no YARV bytecode to show | the bytecode |
| `RubyVM::InstructionSequence#to_binary` of a compiled string | `NotImplementedError`, for the same reason | the bytecode as a String |
| `#each_child` and `#trace_points` of the iseq of a running block or method (`RubyVM::InstructionSequence.of`) | `NotImplementedError`: the binary does not keep the source of a block. The children of a compiled string answer both. | the child iseqs, and the events |
| `Coverage.setup(eval: true)`, then an eval while coverage runs | `NotImplementedError` at the eval: the string is not a file that the build read, so zr cannot measure its lines. A program that asks for eval coverage and never evals gets ruby's result. | the lines of the eval in the result |
| The message of a `SyntaxError` from `RubyVM::AbstractSyntaxTree.parse` | prism's message: zr parses only with prism | the message of ruby's older parser, parse.y |
| `GC::Profiler.raw_data` and `GC::Profiler.result` | an empty list and an empty report: the collector keeps no data for each run | data for each run |
| A method that the program reaches only through a name that it builds at run time, such as `send("ev" + "al", ...)` | `NotImplementedError` when the method needs a part of the runtime that the program did not ask for (the compiler, the normalization tables, pp.rb) | the method's result |

The spec `core/rubyvm/rubyvm_test.rb` "an InstructionSequence answers
eval, to_binary and each_child as ruby does" tests the parts of
`InstructionSequence` that zr supports.

## Details that zr does not copy

| What | zr | ruby 4.0.7 |
|---|---|---|
| The order of `instance_methods`, `methods`, `constants`, `global_variables` and the other lists of names | the order of definition | the order of CRuby's id tables, which comes from the symbols that the boot interned and changes with the installed gems. `core/object/search_test.rb` sorts the lists that it compares. |
| `ObjectSpace.dump` of an object on the heap | the address, the type, the class, `frozen`, the value, the size and `memsize` | also `shape_id`, `slot_size`, `embedded`, `chilled`, `coderange` and `flags`, which describe CRuby's heap |
| `Ripper` on source that does not parse | prism's recovery, translated to Ripper's events | the events of parse.y's own error recovery |
| `$LOADED_FEATURES` after a `require` of a library that ruby ships as a C extension | the files of zr's Ruby port, such as `lib/zr/runtime/ext/etc.rb` and its table of names | one `.bundle` or `.so` file |
| `source_location` and `Method#inspect` of a method that a ported library defines in Ruby, such as `RbConfig.expand` | nil, and no file in `inspect` | the library's file in ruby's own directory and the line |
| rubygems' boot files, such as `bundled_gems.rb` and its `LoadError#message` | loaded only when the program uses `Gem` | loaded before the program starts |
| A `require` of a default or bundled gem | the gem's files from zr's `vendor/ruby`, compiled in; no rubygems code runs | rubygems activates the gem in Ruby code of its own, which a program's redefined methods (such as a counting `Array#each`) see |
| `Gem::Specification`, `Gem.loaded_specs` and `gem` | the gems that zr built the binary with, each active from the start, as under `bundle exec` (lib/zr/runtime/lib/zr/gem_manifest.rb) | every gem installed on the machine |
| A default or bundled gem that is also installed at another version | the version that ruby 4.0.7 ships, from `vendor/ruby` | the newest installed version |
| `RUBY_PLATFORM` and `RbConfig::CONFIG["arch"]` | the platform of the target that zr built the binary for: `arm64-darwin23` (the Darwin version of macOS 14, the oldest macOS that the binary loads on), `aarch64-linux-musl` or `wasm32-wasi` | the platform that ruby was built for, so `arm64-darwin24` for a ruby built on macOS 15 |
| `OpenSSL::OPENSSL_LIBRARY_VERSION` | the OpenSSL library that zr runs on. `OPENSSL_VERSION` is ruby's. | the library that ruby's openssl was built against |
| The core library's own helpers (for example `Packing`) | hidden from `constants`, `ObjectSpace` and the other reflection, but a program that names one (`Packing`, or `const_get`) finds it | not there |

## Library versions

zr carries the pure-Ruby files of ruby 4.0.7's default and bundled gems
at the versions that ruby 4.0.7 ships (`Zr::Stdlib`). The gems with a
C part are zr's own ports (`Zr::Ports`). Five of them are at a later
version than ruby 4.0.7 ships, so their Ruby files and their behavior
are those of the later version:

| Gem | zr | ruby 4.0.7 |
|---|---|---|
| prism | 1.9.0 | 1.8.1 (default gem) |
| json | 3.0.2 | 2.18.0 (default gem) |
| bigdecimal | 4.1.2 | 4.0.1 (bundled gem) |
| syslog | 0.4.0 | 0.3.0 (bundled gem) |
| nkf | 0.3.0 | 0.2.0 (bundled gem) |

ffi 1.17.4 is also a port; ruby 4.0.7 does not ship ffi. The other
ports (psych, digest, openssl, fiddle, racc, date, stringio, strscan,
zlib, io-console, etc, fcntl) are at ruby 4.0.7's versions.

## The locale

A program's locale is UTF-8 on every host: `Encoding.locale_charmap`
returns `"UTF-8"`, and the main file's `__FILE__`, `$0` and `__dir__`
are UTF-8 strings. ruby gets the locale from `LANG` and `LC_ALL` when
the program starts, so under `LANG=C` these three are US-ASCII in
ruby. A build does not read its own locale either: two builds under two
locales write the same bytes (`zr-dev repro`).

## Ruby bugs

| What | zr | ruby 4.0.7 |
|---|---|---|
| A second deadlock after a deadlock that the program rescued (a thread waits on a Queue that no thread feeds, the program rescues the `fatal`, then the main thread waits again) | raises `fatal` "No live threads left. Deadlock?" again | stops responding |
| `String#grapheme_clusters` of a UTF-16 string with a lone lead surrogate before other characters, such as `"a\x00\x00\xD8b\x00"` in UTF-16LE | keeps each character whole: `["a\x00", "\x00\xD8", "b\x00"]` | splits the code units: `["a\x00", "\x00", "\xD8b"]` |
