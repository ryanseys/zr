# Changelog

All notable changes to zr are in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and zr uses
[Semantic Versioning](https://semver.org). Before 1.0, a minor version
can change the command line or the environment variables.

## [Unreleased]

The first public release.

### Added

- `gem install zr` installs the `zr` command on ruby 4.0.7: `run`,
  `build`, `gems`, `inspect`, `diff`, `doctor`, `cache`, `version` and
  `help`. The gem has no dependencies: it carries ruby 4.0.7's
  standard library (`vendor/ruby`), so the install downloads only zr, and
  compiles nothing. zr runs on ruby 4.0.7 or a later 4.0 release.
- A compiled program gives ruby 4.0.7's output byte for byte, or zr
  refuses it at build time with exit status 3. A refusal gives the
  file, the line and the column, the form, the source line with a
  caret, and a link to `docs/reference/support.md`, which lists what
  zr refuses.
- Targets: `aarch64-apple-darwin` binaries and `wasm32-wasi` modules on
  any host, static `aarch64-linux-musl` binaries with a musl toolchain,
  and object files. zr links a macOS binary itself, so it needs no C
  compiler and no linker.
- zr has no C. prism 1.9.0 parses through a Ruby port of its C; zlib is
  a port of zlib 1.3.1; `Regexp` is a port of Onigmo, CRuby 4.0.7's
  engine; json, psych (with libyaml), openssl, socket, digest, date,
  stringio, strscan, bigdecimal, nkf, ffi and others have Ruby ports of
  their C halves. `require "openssl"` in a macOS binary opens the
  host's OpenSSL 3 when it runs.
- A program can require all of ruby 4.0.7's library, and a pure-Ruby
  gem through a literal `$LOAD_PATH`. A program that evals, or requires
  a computed name, carries the compiler (native targets) or a
  tree-walking interpreter (wasm32-wasi).
- ruby runs zr on every host. A build keeps the runtime, the prelinked
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
  what to do for each problem. [How to install zr](docs/how-to/install.md)
  shows how to get ruby 4.0.7, and lists each problem and its fix.
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
- For contributors: `bin/setup`, `bin/minitest`, `bin/console`, the
  `bin/zr` and `bin/zr-dev` binstubs, the `zr-dev` tools, and CI for
  all three targets.
- Two test tiers: `test/unit` (minitest, plain `def test_...`
  methods) and `test/programs`, which `test/programs_test.rb` runs as
  one minitest test for each program. `bin/minitest` runs both, and
  `rake test:unit` and `rake test:programs` run one.
  `ZR_PROGRAMS=core/gc,lang` selects program tests by path,
  `ZR_TEST_HOST=1` runs them on CRuby over zr's kernel,
  `ZR_TEST_FAIL_FAST=1` stops at the first failure, and
  `ZR_TEST_SECONDS` sets the time limit of each program. The program
  tests replace the spec tier
  (`test/spec`, its `zr(...)` and `must_answer` DSL), the e2e tier
  (`test/e2e`) and `programs_test`.
- A program test is a plain Ruby program under
  `test/programs/<area>/`, with ruby's output in files beside it in
  spinel's format (`foo.rb.expected`, `foo.rb.err.expected`,
  `foo.rb.args`, `foo.rb.stdin`), and zr's own files (`.status`,
  `.env`, `.files/`, `.needs`, `.ruby`, `.limits`, `.links`,
  `.<platform>.expected`). Forked workers build each program, and a
  failure prints a unified diff.
  Tests below `test/programs/cli/` build with `zr build`. See
  `docs/reference/program-tests.md`.
- `zr-dev expect [--all] [--check]` writes the expected files of the
  program tests from ruby 4.0.7, in place of `zr-dev oracle` and the
  `zr-dev spec` commands. `zr-dev record` now records only benchmarks.
- The baseline of a target is keyed by the program's path below
  `test/programs`, and the host has a baseline too
  (`test/baselines/aarch64-apple-darwin.txt`).
- A unit test file that builds a program declares
  `# zr-test: runtime` or `# zr-test: eval` in its first lines. A run
  of files without it does not build the runtime. `bin/zr-dev affected`
  maps a change to unit tests and to program tests, and runs them with
  `bin/minitest`.
- `bin/steep check` runs Steep on every file of the compiler. The
  `Steepfile` puts each file in a level (strict, default or lenient).
  Types are inline RBS annotations, and `sig/zr/` holds what inline RBS
  cannot type: `Struct` and `Data` records, `module_function` modules.
  CI runs it after the lint step, and fails if a Steep worker stops.
- `COVERAGE=1 bin/minitest <paths>` measures the line and branch coverage of
  `lib/` with SimpleCov, and writes `tmp/coverage/index.html`. It gates
  nothing.
- `rake lint` has more cops, each with its reason in `.rubocop.yml`:
  the rubocop-performance, rubocop-minitest and rubocop-thread_safety
  plugins, Style cops for one form of quotes, ternaries, semicolons,
  `lambda.call`, rescue modifiers, mutable constants and the core
  collection methods, anonymous block and argument forwarding,
  `Naming/PredicateMethod`, `Style/OptionalBooleanParameter` and
  `Metrics/ParameterLists`. `.rubocop_todo.yml` lists the files that
  are not fixed yet.
- `test/unit/constant_layout_test.rb`: each file of `lib/zr` holds the
  constant that its path names, as in `Zr::Cache::Store` in
  `lib/zr/cache/store.rb`.

### Changed

- A `case` whose `when` values are all symbol literals compares the
  subject with each symbol, with no send of `===`, while no program
  redefines or prepends `Symbol#===`. `bm_case_symbol` takes 0.10 s,
  not 0.68 s.
- The compiler's code has new namespaces, with no change of behavior
  or of output: `Zr::Session` keeps the memos of the process;
  `Zr::Library::*` and `Zr::Cache::*` group the library roots and the
  caches; each `zr` command is a class in `lib/zr/cli/commands/`; the
  build server is the class `Zr::Server`, with `Zr::Server::Client`;
  `Zr::GcTuning` replaces `Tune`; `Runtime.for`, `EvalSupport.for`,
  `Program.build` and `Host.compiled?` replace functions on `module Zr`.
- Tests run with `bin/minitest` (the standard binstub); `bin/test` is
  gone. Program tests are `test/programs_test.rb`, one test per
  program; `ZR_PROGRAMS`, `ZR_TEST_HOST=1`, `ZR_TEST_FAIL_FAST=1`,
  `ZR_TEST_SECONDS` replace bin/test's options. `bin/zr` and
  `bin/zr-dev` are binstubs; `rake build:tools` is gone.

### Removed

- The handoff to a compiled compiler: `exe/zr` no longer gives `run`,
  `build` and `machine` to `bin/zr` or to a compiled compiler in the
  user's cache, and the first build no longer compiles zr. ruby runs
  every command. zr still compiles itself as a check (`zr-dev stage 1`,
  `zr-dev stage 2`, `zr-dev compile --zr`). `rake build:self` and the
  `fast compiler` check of `zr doctor` are gone. `zr cache size` shows,
  and `zr cache clean` deletes, the compiled compilers that older zr
  versions kept in the user's cache (`self-*`, `shipped-*`).
- The platform gems and `zr-dev gem native`. A release ships the
  platform-independent gem only.
- The iseq cache (the `iseq` kind of the store). `exe/zr` loads zr's
  files with plain ruby.
- The variables `ZR_COMPILED`, `ZR_BINARY` and `ZR_ISEQ_CACHE`.
- The `zr machine` and `zr targets` commands. `zr doctor` shows each
  target, its outputs and the outputs that this host can make.
  `zr help build` lists the triples.

### Fixed

- A `return` in a block inside `class << self` leaves the method that
  holds it, also when a method call runs the block.
- A `yield` with keyword arguments passes them as keywords also when
  another thread runs at the yield.
- A child process that a program starts (`posix_spawn` or `exec`) gets
  its standard streams (fds 0 to 2) with `O_NONBLOCK` clear, as ruby
  gives them: a `cat` that reads a pipe from `IO.pipe` waits for the
  bytes, and does not fail with `EAGAIN`.
- `String#*` and `Array.new(n, value)` copy the first part, then the
  copied part again, as ruby does. The number of copies is the log of
  `n`, not `n`.

### Planned for 0.2

- `--gems host`: build with the gems that the host's rubygems has
  installed.
- `zr gem install`: a gem home of zr's own, for gems that a build reads.

[Unreleased]: https://github.com/ryanseys/zr/commits/main
