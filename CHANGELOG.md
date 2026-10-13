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
  `help`. The gem has no dependencies: it carries the pinned ruby's
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
- zr's own code has no C. prism 1.9.0 parses through a Ruby port of its C; zlib is
  a port of zlib 1.3.1; `Regexp` is a port of Onigmo, CRuby's
  engine; json, psych (with libyaml), openssl, socket, digest, date,
  stringio, strscan, bigdecimal, nkf, ffi and others have Ruby ports of
  their C halves. `require "openssl"` in a macOS binary opens the
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
- `SCRIPT_LINES__` keeps the lines of each file that a `load` or a
  `require` runs, in the encoding of the file's magic comment.

### Changed

- `.ruby-version` is the one ruby pin. `mise.toml` is gone.
- `zr-dev gen ruby_version` derives every ruby version fact from
  `.ruby-version` and the CRuby source at that tag.
- zr runs on ruby 4.0 or later. On a ruby of another series than the
  pinned one, zr gives a warning.
- The tests check shapes and relations, not the values of one ruby
  release or build.
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

### Development

- `bin/setup` installs the gems and builds the runtime;
  `bin/minitest` runs the tests, `bin/console` opens IRB with zr
  loaded, and `bin/zr` and `bin/zr-dev` run zr and its tools from the
  checkout. CI runs every target.
- Three test tiers: `test/unit` (minitest, plain `def test_...`
  methods), `test/programs`, which `test/programs_test.rb` runs as one
  minitest test for each program, and `test/ext`, C extensions checked
  against ruby. `ZR_PROGRAMS=core/gc,lang` selects program tests by
  path, `ZR_TEST_HOST=1` runs them on CRuby over zr's kernel,
  `ZR_TEST_FAIL_FAST=1` stops at the first failure, and
  `ZR_TEST_SECONDS` sets the time limit of each program.
- A program test is a plain Ruby program under
  `test/programs/<area>/`, with ruby's output in files beside it in
  spinel's format (`foo.rb.expected`, `foo.rb.err.expected`,
  `foo.rb.args`, `foo.rb.stdin`), and zr's own files (`.status`,
  `.env`, `.files/`, `.needs`, `.ruby`, `.limits`, `.gems`,
  `.<platform>.expected`). Forked workers build each program, and a
  failure prints a unified diff. Tests below `test/programs/cli/`
  build with `zr build`. See `docs/reference/program-tests.md`.
- `zr-dev expect [--all] [--check]` writes the expected files of the
  program tests from the pinned ruby, and `zr-dev record` the recordings
  of the benchmarks.
- The baseline of a target lists the program tests that it may fail,
  keyed by the program's path below `test/programs`, each with its
  reason.
- A unit test file that builds a program declares
  `# zr-test: runtime` or `# zr-test: eval` in its first lines. A run
  of files without it does not build the runtime. `bin/zr-dev affected`
  maps a change to unit tests and to program tests, and runs them.
- `zr-dev rubyspec` and `zr-dev cruby-test` run ruby/spec and CRuby's
  test-all under ruby and in zr binaries, with the gaps as tags and a
  ratchet test. Each test-all tag gives the reason for its gap.
- `bin/zr-dev test` runs any test file, line or program, from anywhere.
  Its options (`--suite`, `--changed`, `--failed`, `--record`, `--verify`,
  `--live`, `--no-build`, `-j` and others) set what `bin/minitest`
  reads.
- `zr-dev fuzz` is a differential fuzzer. It writes typed Ruby programs
  from a seed, mutates the program tests on prism's tree, rewrites
  programs (opaque literals, dead code, moved statements), and breaks
  seeds into junk. It runs each program under ruby and as a zr binary,
  reduces each difference to a small case, buckets it, names the layer
  at fault from a hosted run, and keeps it in `log/fuzz/`. `reduce`,
  `recheck`, `replay`, `report` and `gen --check` work on the cases and
  on the generator.
- The kernel is typed Ruby: plain Ruby with machine types in inline
  RBS comments, which `Machine::Host` also runs on CRuby.
- `bin/steep check` runs Steep on every file of the compiler, with
  inline RBS annotations and `sig/zr/` for what inline RBS cannot
  type. `rake lint` runs RuboCop, each cop with its reason in
  `.rubocop.yml`. `COVERAGE=1 bin/minitest <paths>` measures the
  coverage of `lib/`. `test/unit/constant_layout_test.rb` checks that
  each file of `lib/zr` holds the constant that its path names.

### Planned for 0.2

- `--gems host`: build with the gems that the host's rubygems has
  installed.
- `zr gem install`: a gem home of zr's own, for gems that a build reads.

[Unreleased]: https://github.com/ryanseys/zr/commits/main
