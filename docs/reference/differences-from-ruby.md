# Differences from ruby

zr gives ruby's output, or it refuses
([the contract](../explanation/the-contract.md)). This page lists each
place where zr does not give ruby's output on purpose. There are three
kinds:

- **A refusal.** The result needs something that a compiled program
  does not have, such as YARV bytecode. zr raises `NotImplementedError`
  with a message that gives the method. It does not give a wrong
  result.
- **A ruby bug.** The pinned ruby itself goes wrong, for example it stops
  responding. zr gives the result that ruby's documentation gives, and
  a comment at the code tells the difference.
- **A detail that zr does not copy.** The result comes from how CRuby
  keeps its tables or builds its extensions, and a program cannot
  depend on it portably. zr gives a result that is correct, but not
  the same bytes.

The program tests in `test/programs/` hold zr to each row.

## Refusals

| What | zr | ruby |
|---|---|---|
| `RubyVM::InstructionSequence#disasm`, `#disassemble`, `#to_a` | `NotImplementedError`: zr compiles to machine code, and has no YARV bytecode to show | the bytecode |
| `RubyVM::InstructionSequence#to_binary` of a compiled string | `NotImplementedError`, for the same reason | the bytecode as a String |
| `#each_child` and `#trace_points` of the iseq of a block or method (`RubyVM::InstructionSequence.of`) in a program that names none of `TracePoint`, `Coverage`, `trace_points` and the debug gem | `NotImplementedError`: only a traced build keeps each scope's events and the scopes in it. The children of a compiled string answer both. | the child iseqs, and the events |
| The message of a `SyntaxError` from `RubyVM::AbstractSyntaxTree.parse` | prism's message: zr parses only with prism | the message of ruby's older parser, parse.y |
| A method that the program reaches only through a name that it builds at run time, such as `send("ev" + "al", ...)` | `NotImplementedError` when the method needs a part of the runtime that the program did not ask for (the compiler, the normalization tables, pp.rb) | the method's result |

The programs in `test/programs/core/rubyvm/` test the parts of
`InstructionSequence` that zr supports.

## Details that zr does not copy

| What | zr | ruby |
|---|---|---|
| The order of `instance_methods`, `methods`, `constants`, `global_variables` and the other lists of names | the order of definition | the order of CRuby's id tables, which comes from the symbols that the boot interned and changes with the installed gems. A test that compares such a list sorts it. |
| `ObjectSpace.dump` of an object on the heap | the address, the type, the class, `frozen`, the value, the size and `memsize` | also `shape_id`, `slot_size`, `embedded`, `chilled`, `coderange` and `flags`, which describe CRuby's heap |
| `GC.compact` and `GC.latest_compact_info` | the live objects by type under `considered`, and empty `moved`, `moved_up` and `moved_down`: this collector never moves an object | the objects that the compaction moved, by type |
| A TracePoint that the program reaches only by a name in a string or a symbol, or in code that it builds at run time, such as `Object.const_get("TracePoint")` or `eval("Trace" + "Point.new(:call) { }")` | no events from the program's code, and a warning when the TracePoint is enabled: zr arms the events at build time, when a file's code, or a literal string that an eval form compiles, names `TracePoint`, `set_trace_func` or `Coverage`. `zr run --trace` (or `ZR_TRACE=1`) arms them. | the events |
| `new` in a file that ruby compiled before the program set `RubyVM::InstructionSequence.compile_option` to turn off `specialized_instruction` | a send of Class#new, whose `:c_call` and `:c_return` a TracePoint hears: zr compiles every file before the program runs, so when one file turns the option off, `new` sends in all of them | the file keeps its inline `new`, and a TracePoint hears no Class#new in it |
| `Ripper` on source that does not parse | prism's recovery, translated to Ripper's events | the events of parse.y's own error recovery |
| `$LOADED_FEATURES` after a `require` of a library that ruby ships as a C extension | the files of zr's Ruby port, such as `lib/zr/runtime/ext/etc.rb` and its table of names | one `.bundle` or `.so` file |
| `source_location` and `Method#inspect` of a method that a ported library defines in Ruby, such as `RbConfig.expand` | nil, and no file in `inspect` | the library's file in ruby's own directory and the line |
| rubygems' boot files, such as `rubygems.rb` and `bundled_gems.rb` | loaded only when the program uses `Gem`, so `$LOADED_FEATURES` lists them only then (bundled_gems' `LoadError#message` reads the path from the start, but its warning for a library that left the default gems, such as win32ole, comes only once rubygems loads). In a program that compiles at run time, `Gem` and `RUBYGEMS_ACTIVATION_MONITOR` are autoloads until the first use, so `Object.autoload?(:Gem)` is `"zr/rubygems"` until then | loaded before the program starts |
| A `require` of a default or bundled gem | the gem's files from zr's `vendor/ruby`, compiled in; no rubygems code runs | rubygems activates the gem in Ruby code of its own, which a program's redefined methods (such as a counting `Array#each`) see |
| A library that eval's compiler also uses (json, digest, strscan, cgi/escape, prism), in a program that evals | one copy, which the program shares with the compiler, built as the core library is: a core method that the program redefines (`Hash#merge!`, `Array#pack`) does not change what the library's own code calls, and TracePoint hears no call inside it | the library's Ruby code calls the program's methods, and TracePoint hears it |
| `Gem::Specification`, `Gem.loaded_specs` and `gem`, while rubygems searches the gem directories that the program started with | the default and bundled gems of the ruby install that runs the binary, each active from the first `require` of one of its files, as in ruby, and the gems of the build's Gemfile.lock or `--gem`, each active from the start, as under `bundle exec` (lib/zr/runtime/lib/zr/gem_manifest.rb). A program that points rubygems at other directories (`Gem.use_paths`, `Gem.paths=`) gets rubygems' answers from them, as in ruby | every gem installed on the machine |
| A default or bundled gem that is also installed at another version | the version that the pinned ruby ships, from `vendor/ruby` | the newest installed version |
| `RUBY_PLATFORM` and `RbConfig::CONFIG["arch"]` | the platform of the target that zr built the binary for: `arm64-darwin23` (the Darwin version of macOS 14, the oldest macOS that the binary loads on), `aarch64-linux-musl` or `wasm32-wasi` | the platform that ruby was built for, so `arm64-darwin24` for a ruby built on macOS 15 |
| `OpenSSL::OPENSSL_LIBRARY_VERSION` | the OpenSSL library that zr runs on. `OPENSSL_VERSION` is ruby's. | the library that ruby's openssl was built against |
| The core library's own helpers (for example `Packing`, or a private constant such as `Array`'s `SMALL_ARRAY_LEN`) | hidden from the program: a read, `defined?`, `const_get` and the reflection do not find them, and a program's constant of the same name is its own | not there |
| Threads | green: every thread runs on one OS thread, and a switch happens where a thread blocks or at a safe point once the 100 ms timer fires. `Thread#priority` is kept and read back, but does not change the order. A call into C code (FFI, Fiddle, a port's library call) blocks every thread until it returns. | threads run under the GVL, one at a time, and a blocking C call releases it; the timeslice shrinks or grows with the priority |
| A gem's real C extension (`--native-ext`, [How to use a C extension](../how-to/use-a-c-extension.md)) | runs on macOS on Apple silicon and in a static aarch64-linux-musl binary, with the differences under [C extensions](#c-extensions) | every C extension, on every platform |
| `method(:format) == method(:sprintf)` | false: they are two methods, so that a backtrace names the one that the program called | true: both names define one C function |
| `Ruby::Box` (`RUBY_BOX=1`) | zr links each library into the program. A box's `require` of a library that its own load path does not hold, such as a C extension, runs it once through main and gives the box the constants that it made. All boxes share one rubygems, so one `Gem`. A method that main adds to a core module, such as `Math`, shows in the root box too. zr reads `BUNDLER_SETUP` when it builds the program. | each box loads its own copy of each library, of rubygems and of a C extension, from its own load path |
| Ractors and the collector | one heap for all Ractors: `ObjectSpace.each_object` in a Ractor also finds the unshareable objects of the other Ractors, `GC.stat(scope: :ractor)` counts the whole heap, and no Ractor marks on its own | a heap, counts and an incremental mark for each Ractor |
| How deep Ruby code recurses before `SystemStackError` | about 300,000 frames of a plain method, as Ruby frames are native frames on a 64 MiB stack that zr maps: the main thread's (`MAIN_STACK_BYTES`, lib/zr/runtime/kernel/main.rb, scaled by `RUBY_THREAD_VM_STACK_SIZE` against ruby's 1 MiB default), and each thread's and fiber's (`FIBER_STACK_BYTES`, lib/zr/runtime/kernel/fiber.rb) | about 10,000, from a 1 MiB VM stack. The error, its message and the backtrace's form are the same; the `... N levels...` count in an uncaught error's report differs with the depth. |

### C extensions

A static aarch64-linux-musl binary links a C extension from its objects,
and cannot open OpenSSL. Each extension keeps its own copy of a global
name that another one defines too, also on Linux, where ruby shares one
copy. C that holds the GVL blocks every green thread; C in
`rb_thread_call_without_gvl` runs on a worker thread while the others
run. `TYPE()` of an Exception, a Proc, a Method or a Fiber is zr's own
tag, not ruby's, and C reaches an IO's `struct rb_io` through
`GetOpenFile` only, not through `RFILE(io)` itself. An extension that
hooks trace events (`rb_tracepoint_new`) makes zr build the program with
them. A frame of `rb_profile_frames` is the address of zr's own record
of the code, not ruby's method entry or instruction sequence; the
`rb_profile_frame_*` functions give ruby's answers for it. On macOS, in
`static` and `embed` mode, C++ that throws exceptions and thread-local
variables stop the build; `dynamic` mode runs them.

## The command line

`zr` takes ruby's switches ([`zr` as a ruby](cli.md#zr-as-a-ruby)).
These give other output than ruby's:

| What | zr | ruby |
|---|---|---|
| `--jit`, `--yjit`, `--zjit` and their options | a warning that Ruby was built without that JIT, as a ruby built without JIT support gives; `RubyVM::YJIT` and `RubyVM::ZJIT` are not defined (test/gaps/rubyvm_has_no_yjit_or_zjit_as_a_ruby_built_without_jit_support.rb) | the JIT, when ruby is built with it |
| `-v`, `--version` | zr's version, `zr 0.1.0 (for ruby <version>)` | `RUBY_DESCRIPTION` |
| `-h`, `--help` | zr's usage: short for `-h`, long for `--help` | ruby's list of switches: short for `-h`, long for `--help` |
| `--disable=did_you_mean`, `error_highlight`, `syntax_suggest` | no effect: every program loads them as it starts | the program starts without them |
| `RUBYOPT` of a binary that runs alone | only `-d`, `-w`, `-W`, `-v`, `-E`, `-U`, `--verbose`, `--debug`, `--encoding` and `--backtrace-limit`, as the program starts (lib/zr/runtime/core/rubyopt.rb); `-I`, `-r`, `-K`, `--enable` and `--disable` belong to the build, so `zr build` takes them from its own RUBYOPT | every switch that RUBYOPT can give, after the command line's |
| `-d` | the program's own exceptions | also the `LoadError`s that rubygems' boot rescues, because ruby loads rubygems before every program and zr only before one that uses it |
| `-r` of a library that no directory has | the `LoadError` comes from the prelude that runs the switches | the `LoadError` comes from `Kernel#require` in rubygems |
| `$-i` and `ARGF.inplace_mode` | two values: `-i` sets both, and an assignment sets only its own | one value |

## Library versions

zr carries the pure-Ruby files of the pinned ruby's default and bundled
gems at the versions that it ships (`Zr::Library::Stdlib`). The gems with a
C part are zr's own ports (`Zr::Library::Ports`), except where a build
for this host links the gem's own C extension (json, stringio, strscan,
date, digest, etc, fcntl, bigdecimal, nkf, syslog, rbs, racc, ffi and prism, from the pinned ruby's install). A port can be at a later
version than the pinned ruby ships. Its Ruby files and its behavior are
then those of the later version. `lib/zr/library/ports.rb` gives the
version of each port, and `vendor/vendor.lock` gives the version of each
gem that zr carries.

A Gemfile.lock or `--gem` can select another version of a port's gem
when the port implements its C interface: json 2.20 and 2.21 run on
the json port, which then warns where json 2.x warns (a duplicate key, a
comment) and takes `escape_slash`, as json 2.x's own C part does.

ffi 1.17.4 is also a port; ruby does not ship ffi. The other
ports (psych, digest, openssl, fiddle, racc, date, stringio, strscan,
zlib, io-console, etc, fcntl) are at the pinned ruby's versions.

## The locale

A program reads its locale from `LC_ALL`, `LC_CTYPE` and `LANG` as it
starts, as ruby does: `Encoding.locale_charmap`, the default external
encoding, ARGV and ENV follow it. So do the paths that the system gives:
the main file's `__FILE__`, `$0` and `__dir__`, the main file's lines in a
backtrace and in `caller`, `Dir.pwd` and a directory's entries. A
required file's paths are UTF-8, as ruby gives them on macOS; ruby on
Linux gives them the locale's encoding too. A build does not read its
own locale: two builds under two locales write the same bytes.

## Ruby bugs

zr gives ruby's answer where ruby has a bug, also a wrong one. It gives
another answer only where ruby stops with a crash, stops responding, or
corrupts its own state. This table lists those places.

| What | zr | ruby |
|---|---|---|
| A second deadlock after a deadlock that the program rescued (a thread waits on a Queue that no thread feeds, the program rescues the `fatal`, then the main thread waits again) | raises `fatal` "No live threads left. Deadlock?" again | stops responding |
| `Kernel#singleton_method` with a String that names no Symbol yet, such as `singleton_method("nope_xyz")` | raises `NameError` "undefined singleton method 'nope_xyz' for 'main'", as for a Symbol | the process stops with a segmentation fault when the error builds its message (`rb_sym_to_s` of a NULL name) |
| `String#encode` with two unknown names that are the same, such as `"a\nb".encode("x", "x", newline: :crlf)`, and a newline or `xml:` option | converts with the option and gives BINARY: `"a\r\nb"` | registers a dummy encoding named `""` and warns "invalid name '' for constant"; the next such call raises `ArgumentError` "encoding  is already registered" |
