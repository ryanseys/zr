# Changelog

All notable changes to zr are in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and zr uses
[Semantic Versioning](https://semver.org). Before 1.0, a minor version
can change the command line or the environment variables.

## [Unreleased]

The first public release.

### Added

- `gem install zr` installs the `zr` command on ruby 4.0 or later: `run`,
  `build`, `gems`, `inspect`, `diff`, `doctor`, `cache`, `version` and
  `help`. On a ruby of another series than the pinned one, zr gives a
  warning. The gem has no dependencies: it carries the pinned ruby's
  standard library (`vendor/ruby`), so the install downloads only zr, and
  compiles nothing.
- A compiled program gives the pinned ruby's output byte for byte, or zr
  refuses it at build time with exit status 3. A refusal gives the
  file, the line and the column, the form, the source line with a
  caret, and a link to `docs/reference/support.md`, which lists what
  zr refuses.
- Targets: `aarch64-apple-darwin` binaries and `wasm32-wasi` modules on
  any host, static `aarch64-linux-musl` binaries with a musl toolchain,
  and object files. zr links a macOS binary itself, so it needs no C
  compiler and no linker.
- Linux targets: static `x86_64-linux-musl`, and dynamic
  `x86_64-linux-gnu` and `aarch64-linux-gnu`, which load on glibc 2.35
  and later (Ubuntu 22.04, Debian 12). An x86-64 backend emits
  x86-64-v2 code. A glibc binary links through the host's `cc`,
  exports the C API to the C extensions that it loads, and sorts as
  glibc's `qsort_r` does, so equal elements keep ruby's order there.
  `RUBY_PLATFORM` is `x86_64-linux` or `aarch64-linux`, as ruby gives
  it. `zr inspect` prints the glibc that a binary needs.
- zr's own code has no C. prism 1.9.0 parses through a Ruby port of its C; zlib is
  a port of zlib 1.3.1; `Regexp` is a port of Onigmo, CRuby's
  engine; json, psych (with libyaml), openssl, socket, digest, date,
  stringio, strscan, bigdecimal, nkf, ffi, rbs and others have Ruby ports
  of their C halves, so rdoc, typeprof and repl_type_completor run too. `require "openssl"` in a macOS binary opens the
  host's OpenSSL 3 when it runs.
- A program can require all of ruby's library, and a pure-Ruby
  gem through a literal `$LOAD_PATH`. A program that evals, or requires
  a computed name, carries the compiler (native targets) or a
  tree-walking interpreter (wasm32-wasi).
- zr runs on the host's ruby. A build keeps the runtime, the prelinked
  image and each file's machine code in one content store (`<cache>/store/`), which `zr cache` shows and
  cleans. Each build names in a root what the next build needs, so a
  clean keeps it, and an installed zr evicts the entries used longest
  ago to stay under `ZR_CACHE_MAX_GB`.
- `zr run` and `zr build` read another version of a gem from
  `--gem NAME=VERSION` or `--gem NAME=DIR`, and from the Gemfile.lock
  of `--gemfile` or `BUNDLE_GEMFILE`, before zr's standard library. zr
  reads the lock with its own copy of bundler and needs no `bundle exec`. A gem with a C
  extension that zr does not port, or a port's gem outside the
  versions whose C zr implements, stops the build at its `require`.
- `zr gems` lists the gems that a build reads and where each comes
  from. Each binary carries a manifest of its gems, which
  `zr inspect` and `zr build --print-gems` print. `zr diff` runs a
  program under ruby and as a zr binary, and names and shows the
  difference.
- A literal `require` in the program's own files that zr cannot find
  stops the build with the fix, unless `rescue LoadError` guards it
  or the build has `--allow-runtime-require`.
- `zr doctor` checks the ruby, the host, each target, wasmtime, OpenSSL,
  the standard library and the cache, and says
  what to do for each problem. [How to install zr](https://github.com/ryanseys/zr/blob/v0.1.0/docs/how-to/install.md)
  shows how to get ruby, and lists each problem and its fix.
- An error prints one line and no backtrace (`ZR_DEBUG=1` shows it).
  A bad `ZR_*` value exits with status 2 and names a value that works.
  Ctrl-C exits with status 130. Every command takes `--help`, and a
  mistyped command gets a suggestion.
- The first build says that it builds the runtime, which takes some
  minutes one time. Two builds at once build the runtime one time.
- A binary loads on macOS 14 or later, and its `RUBY_PLATFORM` is
  `arm64-darwin23`, the platform of macOS 14. A glibc aarch64 Linux
  runs the static `aarch64-linux-musl` binary, and links it with
  `musl-gcc` or `$CC`. On a host that runs no native target, `zr run`
  says to use `--emit wasm`.
- MIT License. `THIRD_PARTY_NOTICES.md` names every part from other
  work, and `licenses/` holds the license texts that have no other copy
  in the gem.
- Documentation in `docs/`: tutorials, how-to guides, reference and
  explanation, with a performance page and a support page that
  `zr-dev gen` writes from the benchmark reports and from the compiler.
- A program can run a gem's real C extension (`--native-ext NAME`, or
  `ZR_NATIVE_EXT`) through zr's own copy of ruby's C API, on
  macOS and in a static aarch64-linux-musl binary. `--ext` chooses
  whether the binary links the extension's objects (the default),
  embeds its bundle, or loads the bundle when it runs. When the gem's
  install kept no compiled code, zr runs its `extconf.rb` and builds
  it. `zr doctor` counts the installed gems whose extension is ready.
- `zr` is also a ruby: when its first word names no command, it takes
  ruby's command line (`zr app.rb`, `zr -e CODE`, `zr -lane ...`), and
  builds and runs the program as `zr run` does.
- A `case` whose `when` values are all symbol literals compares the
  subject with each symbol, with no send of `===`, while no program
  redefines or prepends `Symbol#===`.
- `zr -h` prints a short usage that fits a terminal of 80 by 25.
  `zr --help`, `zr help` and `--dump=help` print the full usage, in lines
  of at most 80 columns.
- A fatal signal, a runtime bug and `rb_bug` write ruby's bug report
  (`[BUG]`) to the file or command that `RUBY_CRASH_REPORT` or
  `--crash-report` names, and end the program by the signal.
- zr gives the behavior of ruby 4.1, the pinned ruby: a `Regexp` and the
  result of `Symbol#to_s` are frozen; `&nil` block parameters and nested
  `for` targets compile; `Ruby::SourceRange`, `#source_range`,
  `#syntax_tree`, `Ruby::Prism` and `Proc#refined` are there; so are
  `Integer#bit_count`, the bit methods of `String`, `Module#descendants`,
  `Range#clamp`, `MatchData#integer_at`, `ENV.fetch_values`, `Dir.scan`,
  `autoload_relative`, and pack's `R`, `r`, `x!`, `@!` and `^`. Ractors
  follow 4.1's rules for class ownership, ports, `value` and `monitor`.
  `GC.stat` takes `scope:`, and `IO::Buffer` is split into `Storage` and
  `Slice`. The messages that 4.1 changed are 4.1's.
- The ports follow the C of the gems that ruby 4.1 ships (openssl, date,
  digest, psych, stringio, io-console, bigdecimal and prism). The C API
  follows 4.1's layouts and functions, also for a bundle that links
  ruby's shared library.
- `SCRIPT_LINES__` keeps the lines of each file that a `load` or a
  `require` runs, in the encoding of the file's magic comment.
- TracePoint and Coverage give ruby's events and counts:
  - `:c_call` fires for the methods that ruby's C calls by name, such as
    a Symbol block's send and an `Enumerator#each`;
  - `TracePoint#enable(target_line:)` refuses a line that the target
    never fires;
  - `Coverage.start(branches: true)` counts every branch, also in eval
    code and in files required at run time, and in walked eval code;
  - `oneshot_lines` lists each line in the order of its first run;
  - a `-r` library that starts Coverage measures the main script.
- `RubyVM::InstructionSequence` gives debugger-grade ISeqs without
  instructions: `of` a method, block, class body or backtrace location,
  `each_child`, `trace_points`, `node_id`, `script_lines`, `to_a`'s
  header and `RubyVM::INSTRUCTION_NAMES`. The debug gem's line
  breakpoints resolve when their file loads.
- `IO#close` interrupts each fiber that waits on the IO through its
  scheduler's `fiber_interrupt`, as ruby does.
- `Integer::GMP_VERSION`, `Time::tm`, and a `RubyVM` without `YJIT` and
  `ZJIT`, as on a ruby built without JIT support; `--jit`, `--yjit` and
  `--zjit` warn as such a ruby does.
- `zr` run under the name `ruby` answers `--version` with ruby's
  description, and names itself in its errors.
- A program with eval support keeps the machine code of each file and
  eval string that it compiles as it runs, and its next run maps that
  code with no compile (`<cache>/store/loaded/`; `ZR_CODE_CACHE=0`
  turns it off). `zr run` also keeps the binary of such a program when
  a require stays for the run time.
- A default or bundled gem is active from the first `require` of one of
  its files, as in ruby, and `Gem::Specification` lists every default
  and bundled gem of ruby's install, also in a binary that runs where
  no zr is installed. Only the gems of the build's Gemfile.lock or
  `--gem` are active from the start.
- A program's own `Kernel#require` (bootsnap's, zeitwerk's, a test's
  stand-in through `define_method`) hears each literal `require`, also
  of a file that the build compiled in.
- A binary reads RUBYOPT as it starts: `-d`, `-w`, `-W`, `-v`, `-E`, `-U`
  and `--backtrace-limit`, before the switches of its build.
- A build for this host links json's own C extension, as the pinned ruby
  installed it, in place of zr's port (`ZR_NATIVE_EXT=-json` keeps the
  port). A json outside the versions that the port implements builds
  without its C part, or with its own C under `--native-ext`, where it
  used to stop the build.
- stringio, strscan, date, digest, etc, fcntl, bigdecimal, nkf, syslog,
  rbs, racc, ffi, prism and zlib link their own C extensions too, the default gems' from the pinned ruby's arch directory:
  stringio passes more of its own tests than its port did. The C
  API gains the transcoder (`rb_econv_*`), `rb_check_funcall`,
  `rb_check_id`, `rb_ext_resolve_symbol` and the other functions that
  their C calls.
- Core methods take an argument that only converts, as CRuby's C takes
  it, also a BasicObject that undefines every method: an object with
  `begin`, `end` and `exclude_end?` as a Range, an object whose `to_io`
  gives an IO for File's times and FileTest's checks, and `to_str`,
  `to_int`, `to_f` or `to_path` where the C converts with them. The
  core's comparisons by identity and its truth tests send nothing to
  the argument.
- Calls make no more Arrays or Hashes than ruby's VM, in each of CRuby's
  allocation checks of method calls and Proc#call: a splat's arguments
  go on a reused per-task stack, a lone `**h` is lent to the callee and
  copied only where the callee keeps it, a kwrest keeps the Hash that
  the call built, and a def whose `...` only forwards passes its
  arguments on in place. A yield passes keywords as a call does.
- A program reads the `RUBY_GC_*` variables as it starts, as ruby does,
  and under `-w` reports each value it reads or ignores in ruby's words.
  `RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR` sets when a major collection runs.
- An object becomes old after it lives through three collections, as in
  ruby, so a short-lived object does not wait in the old generation for a
  major collection. `ObjectSpace.dump` gives its age and generational
  flags as ruby does.
- The heap gives memory back: a full collection returns each free page,
  also in a part of the heap that still holds live objects, and a heap
  keeps free room for its live set as a whole, not for each cell size.
  An eval loop, and classes or refinements made in a loop, keep the
  process's memory flat. `Process.warmup` makes each object it keeps old.
- A String keeps its coderange as ruby does, and `ObjectSpace.dump` writes
  it, `"unknown"` until a scan. `Process.warmup` scans each String and
  gives back every empty page of the heap.
- Unicode case mapping, case folding and `String#inspect` run about eight
  times faster, and long Integers' bitwise operators, shifts, squares,
  divisions and `Integer.sqrt` faster too (`Integer.sqrt` of a 90,000-bit
  square took a minute).
- Each thread runs on an OS thread of its own under a GVL, on macOS and
  Linux, as in ruby: C without the GVL (`rb_thread_call_without_gvl`, an
  FFI function with `blocking: true`, Fiddle) runs on its thread while
  the others run, `Thread#native_thread_id` is the OS thread's id, traps
  run on the main thread, and a fork keeps only the thread that forked.
  `ZR_THREADS=green` puts every thread on one OS thread, as on wasm.
- `Ruby::Box` (`RUBY_BOX=1`, as in ruby: no other value enables it) prints
  ruby's experimental notice after the program's switches, so
  `-W:no-experimental` silences it.
- A `Ruby::Box` starts with a copy of the load path as the program started
  with it, and its `require` of a Ruby library on that path runs a copy of
  the library for the box, nested requires included.
- A binary runs its compiled-in libraries where they are not on disk. The
  install prefix (`ZR_PREFIX`) defaults to the directory that the build
  compiled ruby's library from, not `~/.zr`, so `$LOAD_PATH` names the
  compiled files. `File.exist?`, `File.file?` and `File.readable?` find
  such a file, and the files that a library reads as data by a path from
  its own directory (`File.read(File.join(__dir__, ...))`, as rubygems
  does) are carried in the binary. A library that searches the load path
  for files to `Kernel.load` (irb's locale messages) finds them too.

[Unreleased]: https://github.com/ryanseys/zr/commits/main
