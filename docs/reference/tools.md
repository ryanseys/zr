# Tools

A checkout has scripts and binstubs in `bin/`, a small set of rake tasks, and
the `zr-dev` tool. The rake tasks build, test, lint, generate and
release. The other maintainer tools are `zr-dev` commands.

For the `zr` command itself, see [The `zr` command](cli.md). For the
steps to run the tests, see [How to run the tests](../how-to/run-the-tests.md).

## Scripts

| Script | Does |
|---|---|
| `bin/setup` | Installs the gems (`bundle install`), sets up the reference ruby (`tool/install_reference_gems.rb`) and builds the runtime for this host (`rake build`). It tells you if wasmtime is not installed. |
| `ruby tool/install_reference_gems.rb` | Installs the gems of the ruby that every expected output comes from, into `tmp/reference/gems`: ruby 4.0.7's bundled gems, and zr's versions of the gems whose C it ports (`lib/zr/library/ports.rb`). It installs only the missing gems, tells you about other versions in the directory, and then writes `tmp/reference/STAMP`. `bin/setup` runs it. `expect`, `record`, `probe` and the program tests run ruby with only these gems (`test/support/harness/reference.rb`). |
| `bin/minitest [paths] [minitest options]` | Runs the tests (minitest's own binstub). With no paths, it runs every `test/**/*_test.rb`: the unit tests and the program tests (`test/programs_test.rb`). It builds the runtime first if the tests need it and it is not built. |
| `bin/zr` | The binstub of `exe/zr`, the `zr` command of this checkout. |
| `bin/zr-dev` | The binstub of `tool/zr-dev.rb`, the [`zr-dev`](#zr-dev) commands. |
| `bin/console` | Starts IRB with zr loaded. |
| `bin/steep check` | Checks the types of every file of the compiler, with the Steep of this checkout's bundle, at the level (strict, or default for two record files) that the `Steepfile` gives the file. Types are inline RBS annotations (`#:`, `# @rbs`), and `sig/zr/` holds what inline RBS cannot type. Give it no paths: with paths, Steep 2.1 checks nothing and reports no error. It stops with a status that is not 0 when Steep finds an error. CI runs it after the lint step through `.github/scripts/steep.rb`, which also fails when a Steep worker stops on an exception (Steep then leaves the file unchecked and exits 0). |

A `bin/minitest` path is a test file or a directory of test files
(`bin/minitest test/unit`), and `path:line` runs the test at that line.
The minitest options follow the paths: `-i` (or `-n`) selects tests by
name, `-e` leaves them out, `-s` sets the seed, and `-v` shows each
test (`bin/minitest test/unit -i /blocks/`). Each program is one test,
named `test_<path below test/programs>`, so
`bin/minitest test/programs_test.rb -i /stdlib.uri/` selects programs
by name.

`bin/minitest` reads these environment variables. `rake test` and the
tier tasks read them too, because they call `bin/minitest`.

| Variable | Effect |
|---|---|
| `ZR_PROGRAMS=<paths>` | Runs only the program tests below these paths of `test/programs`, separated by commas (`ZR_PROGRAMS=core/gc,lang`). A path is a directory or one program. |
| `ZR_TEST_HOST=1` | Runs the program tests on CRuby over zr's kernel, with no build (`zr-dev host`). The baseline is `test/baselines/host.txt`. |
| `ZR_TARGET=<triple>` | Builds and runs the programs for that target. |
| `ZR_GC_STRESS=1` | Collects at every allocation. |
| `ZR_TEST_FAIL_FAST=1` | Starts no more tests after one fails. |
| `ZR_TEST_SECONDS=<n>` | The time limit of each program run and build (default 60). `ZR_TEST_TIMEOUT=0` also lifts the time limit of each test in a worker (default 180). |
| `SLOW=1` | Also reports the 25 slowest files and the 20 slowest tests. `SLOW=<n>` with `n` > 1 reports `n` tests. |
| `MT_CPU=<n>` | The number of worker processes. The default is one for each 2 GB of memory, with a quarter of the memory (at least 4 GB) and two cores kept free. |

To time a run, use the shell's `time` (`time bin/minitest test/unit`).

All the test variables are in
[Environment variables](environment-variables.md#for-the-tests).

## Rake

`rake -T` lists every task. The `Rakefile` loads the bundle, so
`rake <task>` needs no `bundle exec`. The rake tasks take no paths and
no arguments. Give paths and minitest options to `bin/minitest`.

### Build

| Task | Does |
|---|---|
| `rake build` | Builds the runtime for this host: the runtime object, the prelinked image and eval support. `bin/minitest` also does this when the runtime is not built. |
| `rake build:wasm` | Builds the runtime for `wasm32-wasi`. |
| `rake build:all` | Builds the runtime for this host and for `wasm32-wasi`. |

### Test, lint and generate

| Task | Does |
|---|---|
| `rake` | `rake lint`, then `rake test`. |
| `rake test` | The two tiers: unit, programs. |
| `rake test:unit` | The unit tier: zr's own internals (`test/unit`). |
| `rake test:programs` | The program tests: Ruby programs that zr builds, each checked against ruby 4.0.7 (`test/programs_test.rb`). |
| `rake lint` | Runs RuboCop with the cops that `.rubocop.yml` turns on. |
| `rake gen` | Writes every generated file again (`zr-dev gen all`). `CHECK=1 rake gen` writes nothing, and fails if a file is out of date. |

To run some test files, give their paths to `bin/minitest`:
`bin/minitest test/unit/cli_test.rb`, `bin/minitest test/unit -i /blocks/`,
or `ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb`. For the
report of the slowest files and tests, set `SLOW=1`: `SLOW=1 rake test:unit`, or
`SLOW=1 bin/minitest test/unit/cli_test.rb`. `COVERAGE=1` measures the
line and branch coverage of `lib/` (not `lib/zr/runtime`, which zr
compiles and ruby does not run) with SimpleCov, and writes the report
to `tmp/coverage/index.html`. Give it paths: `COVERAGE=1 bin/minitest
test/unit/bytes_test.rb`. It gates nothing.

### Gem and release

| Task | Does |
|---|---|
| `rake release` | Builds the gem, tags the version and pushes the gem to rubygems.org, from your machine. The release workflow does not use it; see [How to release zr](../how-to/release.md). |
| `rake gem:build` | Builds `pkg/zr-<version>.gem`. |
| `rake gem:install`, `rake gem:install:local` | Builds the gem and installs it. |
| `rake gem:build:checksum`, `rake gem:clean`, `rake gem:clobber` | Bundler's other gem tasks. |

`rake build` builds the runtime, not the gem. Bundler's `build`,
`install` and `release` tasks are under `gem:`.

## zr-dev

`zr-dev` holds the tools that work on a checkout. Run it with the ruby
of the checkout, from any directory:

```
$ ruby tool/zr-dev.rb help                 # every command
$ ruby tool/zr-dev.rb bench --help         # the options of one command
$ ruby tool/zr-dev.rb gems help            # the commands of a group
```

The tables below write `zr-dev` for `ruby tool/zr-dev.rb`. The binstub
`bin/zr-dev` does the same (see [The binstubs](#the-binstubs)). The code of
each command is in `tool/<command>.rb`. The header comment of each file
gives more examples.

### Tests

| Command | Does |
|---|---|
| `zr-dev affected [--base REVISION] [--dry-run]` | Runs the tests that a change can reach, with `bin/minitest`: the unit test files by path, and the program tests through `ZR_PROGRAMS`. It reads the diff against `main`, or against `--base`, and maps each changed file to unit tests and program tests (`tool/affected.rb`): a changed test to itself, a file beside a program to the program, a core class to its program tests, a library to its `stdlib/` area and the programs that require it, and a file under `lib/zr` that does not change a build to the unit tests that load it. If the change can reach everything (the compiler, the kernel, the test support), it runs nothing and says so. `--dry-run` prints the test paths and runs nothing. |
| `zr-dev vendor` | Writes `vendor/` (ruby 4.0.7's own library from its source at `RUBY_REVISION`, the bundled gems and the port gems from their `.gem` files, prism's templates from its tag), `vendor/vendor.lock` and `lib/zr/library/stdlib.rb`, from `lib/zr/library/vendor.rb`, `lib/zr/library/ports.rb` and `lib/zr/version.rb`. It needs `RUBY_SRC` and `PRISM_SRC`. See [How to update the vendored code](../how-to/update-vendored-code.md). |
| `zr-dev vendor --check` | Checks each file of `vendor/` against the lock, offline. |
| `zr-dev vendor outdated` | Lists the gems of `vendor/` that have a newer release on rubygems.org. |
| `zr-dev vendor diff GEM [VERSION]` | Lists the files that change from the locked GEM to VERSION (default: the newest), and zr's files under `lib/zr/runtime/` that replace one of them. |

### Gems

[How to check a gem](../how-to/check-a-gem.md) tells more. A gem is `NAME`, `NAME=VERSION` or the path of an unpacked gem. `--corpus DIR` (or `ZR_GEM_CORPUS`) finds each gem first in `DIR/<name>`; `--offline` fetches nothing.

| Command | Does |
|---|---|
| `zr-dev gems try GEM [--keep] [--save]` | Fetches the gem and the gems that it needs (ruby platform only), builds a program that requires it, runs the program under ruby 4.0.7 and as a zr binary, and prints the tier, the diff and the path of the log (`tmp/gems/logs`). `--keep` keeps the work directory. `--save` writes the row into `gems/compat.tsv`. |
| `zr-dev gems sweep [GEM...] [--top N] [--jobs N] [--save]` | Tries many gems, one line each, then counts the tiers. `--top N` adds the N most downloaded gems of `gems/top.tsv`. The rows go into `tmp/gems/sweep-<time>.tsv`, or with `--save` into `gems/compat.tsv`. |
| `zr-dev gems triage [KIND] [--file TSV]` | Groups the gems that do not load by the kind of failure, the kind that stops the most gems first. With `KIND`, it gives each gem of that kind with its detail. |
| `zr-dev gems top [--refresh] [--count N]` | Prints the most downloaded gems with their tiers. `--refresh` writes `gems/top.tsv` again from packages.ecosyste.ms. |
| `zr-dev gems snapshot [REVISION] [--list] [--remove DIR]` | Makes a copy of zr at a commit (HEAD by default) in `tmp/gems/zr/<commit>`, a git worktree with its own cache, and builds its runtime, as `rake build` does. `try` and `sweep` take `--zr DIR` (or `ZR_GEMS_ZR`) to build with the copy, so zr can change in the checkout while a sweep runs. |

### Expected outputs

| Command | Does |
|---|---|
| `zr-dev expect [--all] [--check] [path...]` | Runs each program test under ruby 4.0.7, in a run directory as the test does, and writes its files beside it: `foo.rb.expected`, and `foo.rb.err.expected` and `foo.rb.status` when they are not empty and not `exit 0` (`tool/expect.rb`). On Linux, it writes `foo.rb.linux.expected` when the stdout is different. With no path, it takes `test/programs`. It writes only a test whose `foo.rb.expected` is missing or older than the program; `--all` writes each test. `--check` writes nothing, lists each test whose files differ from ruby, and fails if there is one. See [Program tests](program-tests.md#expected-output). |
| `zr-dev record [--again] <benchmark>...` | Runs a benchmark under ruby 4.0.7 and writes its recording (`.out`, `.err`, `.status`, `.signal`) beside it. It takes only paths below `benchmark/`. It does not change a benchmark that has a recording. `--again` writes the recording again. See [Benchmark recordings](test-format.md). |
| `zr-dev rubyspec <area>... [-f PATTERN] [-j JOBS] [--keep]` | Runs ruby/spec from the CRuby checkout at `RUBY_SRC` (at `Zr::RUBY_REVISION`) under ruby 4.0.7 and in a zr binary, one spec file per process with a limit of 60 s, and lists each example that passes in ruby and fails in the binary. An area is a directory of `spec/ruby`, such as `language` or `core/array`; `core` and `library` are each of their directories. `-f` selects the spec files whose path matches. The report of each area is in `tmp/rubyspec/<area>.txt`, and `tmp/rubyspec/summary.tsv` has a line for each area. |

### Generated files

Each generator writes a file from ruby 4.0.7, or from a CRuby source at
the revision of ruby 4.0.7. The file starts with a header that tells
this. Do not edit a generated file by hand. A generator that reads a
table from the running ruby stops on a ruby that is not 4.0.7.

Every generator takes `--check`. With `--check`, it writes nothing, and
it fails if the file is out of date. `zr-dev gen all` runs every
generator in order (`rake gen` runs it too).

The generators read the CRuby source from the checkout that `RUBY_SRC`
names (default `~/dev/github.com/ruby/ruby` when it exists, else
`tmp/ruby`), at `Zr::RUBY_REVISION` (`lib/zr/version.rb`). They read
prism from `PRISM_SRC` (default `~/dev/prism` when it exists, else
`tmp/prism-1.9.0`). With no checkout there, a generator stops and says
which `git clone` to run. The code of each generator is
in `tool/gen/`.

| Command | Writes |
|---|---|
| `zr-dev gen features` | `lib/zr/hir/features.rb`: the names that `require` accepts |
| `zr-dev gen unicode` | `lib/zr/runtime/core/unicode.rb`: case mappings |
| `zr-dev gen encodings` | `lib/zr/runtime/core/encodings.rb`: the encoding registry |
| `zr-dev gen transcode` | `lib/zr/runtime/core/transcode.rb`: single-byte encoding tables |
| `zr-dev gen cjk` | `lib/zr/runtime/core/cjk.rb`: multibyte encoding tables |
| `zr-dev gen enc_mb` | `lib/zr/runtime/kernel/enc_mb.rb`: multibyte encoding descriptors |
| `zr-dev gen onig_unicode` | `lib/zr/runtime/core/regexp/unicode_tables.rb` and `lib/zr/runtime/kernel/onig_tables.rb`: Onigmo's Unicode tables, from CRuby's `enc/unicode` at `RUBY_SRC`. Both files come from one computed value; `test/unit/onig_unicode_test.rb` checks that they agree. |
| `zr-dev gen onig_encodings` | `lib/zr/runtime/core/regexp/onig/encoding_tables.rb`: Onigmo's encodings past UTF-8, from CRuby's `enc/*.c` |
| `zr-dev gen nkf [--source PATH]` | `lib/zr/runtime/ext/nkf/tables.rb`: nkf's conversion tables, from the installed nkf gem's `utf8tbl.c` (or `NKF_SRC`) |
| `zr-dev gen zlib_tables` | `lib/zr/runtime/kernel/zlib_tables.rb`: the tables that zlib 1.3.1 computes |
| `zr-dev gen openssl_constants` | `lib/zr/runtime/ext/openssl/ossl/constants.rb`: openssl's Integer constants. Not in `gen all`: the order comes from the host's OpenSSL build, so read the diff. |
| `zr-dev gen emoji` | `lib/zr/runtime/core/emoji.rb` |
| `zr-dev gen builtin_lines` | `lib/zr/runtime/core/builtin_lines.rb` |
| `zr-dev gen tables` | This OS's errno, fcntl, etc and socket tables, into `lib/zr/runtime/core/os/<os>/` and `lib/zr/runtime/ext/os/<os>/`. The socket table reads `ext/socket/mkconstants.rb` from `RUBY_SRC`, or from the copy that `MKCONSTANTS` names. |
| `zr-dev gen gem-compat` | `docs/reference/gem-compat.md`: how far each gem gets with zr, from `gems/compat.tsv`. It runs no gem; `zr-dev gems sweep --save` writes the table. |

#### Generated files that the unit tier tests

The unit tier writes these four files again and compares them with the
committed files. Thus a file that is out of date makes a test fail.

| Command | Writes | Tested by |
|---|---|---|
| `zr-dev gen libsystem` | `lib/zr/obj/macho/libsystem.rb` | `test/unit/libsystem_test.rb` |
| `zr-dev gen prism` | `lib/zr/runtime/ext/prism/ruby/*.rb`, from the templates in `tool/gen/prism/templates` | `test/unit/prism_test.rb` |
| `zr-dev gen prism_encoding_tables` | `lib/zr/runtime/ext/prism/ruby/encoding_tables.rb` | `test/unit/prism_test.rb` |

`ZR_BLESS=1 bin/minitest test/unit/description_test.rb` also writes the
descriptions again. `ZR_BLESS=1` on `test/unit/libsystem_test.rb`
writes the libSystem list again. See
[How to run the tests](../how-to/run-the-tests.md#accept-a-new-snapshot).

### Measure

| Command | Does |
|---|---|
| `zr-dev bench [--runs N] [--target TRIPLE] [filter...]` | Builds each program in `benchmark/`, checks its output, and times it beside `ruby` and `ruby --yjit`. `--runs` sets the runs of each program (default 5). `--target` sets the target to build for. The words select benchmarks by name: `zr-dev bench --runs 5 fib`. |
| `zr-dev bench --check [before after]` | Compares the newest report with the one before it, and runs nothing. With two arguments, it compares those two reports, given as paths or revisions. |
| `zr-dev compile [--runs N] [--write] [--zr [--commit \| --check]] [filter...]` | Times how long zr takes to compile each rung of `benchmark/compile/`, phase by phase. `--runs` sets the builds of each rung, after one warmup (default 3). `--write` writes the table to `tmp/bench/compile.txt`. `--zr` also builds the compiled compiler with ruby (`tmp/compile/zr`), and times it. The words select rungs by name. |
| `zr-dev compile --zr --commit` | Also writes a baseline to `benchmark/results/compile/`. |
| `zr-dev compile --profile runtime\|eval` | Lowers the runtime or eval support object, then times the passes and the assembly of each function, one at a time. It prints the sums and the 20 slowest functions, and writes all of them to `tmp/bench/profile-<object>.tsv`. |
| `zr-dev compile --zr --check` | Fails if the compiled compiler is slower than the newest baseline in `benchmark/results/compile/`. |
| `zr-dev host <file.rb> [args...]` | Runs a program on CRuby with no build: the kernel runs as Ruby (`Machine::Host`), and a walker runs the core library, the gem prelude and the program over the kernel's heap (`Machine::Host::Walk`). The exit status is the program's. It is much slower than a binary. `ZR_TEST_HOST=1 bin/minitest test/programs_test.rb` runs the program tests this way. |
| `zr-dev probe [-j JOBS] <file.rb\|dir>...` | Runs each Ruby file under ruby 4.0.7 and as a zr binary, and prints a unified diff of each part that differs: stdout, stderr, the exit status and the signal. It compiles each file in a fork of one process that has the compiler and the runtime loaded. A directory means its `.rb` files. `-j` sets the probes at a time (default 4). |
| `zr-dev golden save\|check [LABEL]` | Lowers the kernel on `aarch64-apple-darwin`, `aarch64-linux-musl` and `wasm32-wasi`, and writes (`save`) or compares (`check`) one line for each fact a build sees: each function's IR fingerprint, each datum, the raw functions, the kernel's description and the symbol names, in `tmp/golden/LABEL/` (default `base`). A change to the kernel's spelling must keep it the same. |

See [How to measure performance](../how-to/measure-performance.md).

### Self-compile checks

| Command | Does |
|---|---|
| `zr-dev stage 1` | Compiles the compiler (`exe/zr`) two times, in two processes with two caches, and compares the compiler objects and the runtime objects byte for byte. |
| `zr-dev stage 2` | Builds `exe/zr` with ruby, then builds it again with that binary (`tmp/stage1/zr build exe/zr`), and compares the two binaries. It takes about ten minutes and 5 GB of memory. |

See [Bootstrapping](../explanation/bootstrapping.md).

### Build server

| Command | Does |
|---|---|
| `zr-dev serve [--idle MINUTES] [--socket PATH]` | Keeps one warm compiler for the edit loop: the compiler loaded, YJIT warm, and the runtime's description, symbols and prelinked images in memory. While it runs, each `zr run` and `zr build` of this checkout sends it the build. The server forks one child for each build. The client then runs the program itself, so the program keeps the terminal, the signals and the exit status. A Ctrl-C in the client stops the build. The server starts again when a file of zr that it loaded changes, and stops after `--idle` minutes with no request (default 30). It listens at `<cache>/server.sock`. `ZR_SERVER=0` makes a command build alone, and `ZR_SERVER=PATH` uses the server at `PATH`. After an edit to a core file, `zr run` of hello took 4.2 s with the server and 4.9 s without it. After an edit to a program, it took 0.23 s against 0.25 s (hello) and 0.40 s against 0.46 s (a program with eval). The server holds about 700 MB. |

## The binstubs

`bin/zr` and `bin/zr-dev` are binstubs, as the gems' binstubs in `bin/`
are: each one loads its Ruby entry point (`exe/zr`, `tool/zr-dev.rb`)
under the ruby that runs it. Nothing is compiled first.
