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
| `ruby tool/install_reference_gems.rb` | Installs the gems of the ruby that every expected output comes from, into `tmp/reference/gems`: the pinned ruby's bundled gems, and zr's versions of the gems whose C it ports (`lib/zr/library/ports.rb`). It installs only the missing gems, tells you about other versions in the directory, and then writes `tmp/reference/STAMP`. `bin/setup` runs it. `zr-dev expect`, `zr diff` and the program tests run ruby with only these gems (`test/support/harness/reference.rb`). |
| `bin/minitest [paths] [minitest options]` | Runs the tests (minitest's own binstub). With no paths, it runs every `test/**/*_test.rb`: the unit tests and the program tests (`test/programs_test.rb`). It builds the runtime first if the tests need it and it is not built. |
| `bin/zr` | The binstub of `exe/zr`, the `zr` command of this checkout. |
| `bin/zr-dev` | The binstub of `tool/zr-dev.rb`, the [`zr-dev`](#zr-dev) commands. |
| `bin/console` | Starts IRB with zr loaded. |
| `bin/steep check` | Checks the types of every file of the compiler, and of the kernel with this host's layers (the `kernel` target; `ZR_KERNEL_OS=darwin`, `linux` or `wasi` with `--group=kernel` checks one target's), with the Steep of this checkout's bundle, at the level (strict, or default for two record files) that the `Steepfile` gives the file. Types are inline RBS annotations (`#:`, `# @rbs`), and `sig/zr/` holds what inline RBS cannot type. Give it no paths: with paths, Steep 2.1 checks nothing and reports no error. It stops with a status that is not 0 when Steep finds an error. CI runs it after the lint step through `.github/scripts/steep.rb`, which also checks the kernel of the other targets, and fails when a Steep worker stops on an exception (Steep then leaves the file unchecked and exits 0). |

A `bin/minitest` path is a test file or a directory of test files
(`bin/minitest test/unit`), and `path:line` runs the test at that line.
The minitest options follow the paths: `-i` (or `-n`) selects tests by
name, `-e` leaves them out, `-s` sets the seed, and `-v` shows each
test (`bin/minitest test/unit -i /blocks/`). Each program is one test,
named `test_<path below test/programs>`, so
`bin/minitest test/programs_test.rb -i /stdlib.uri/` selects programs
by name.

`bin/minitest` reads the variables of
[Environment variables](environment-variables.md#for-the-tests). `rake test` and the tier
tasks read them too, because they call `bin/minitest`, and the options
of `zr-dev test` set most of them.

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
| `rake test` | The three tiers, unit, programs and ext, in one `bin/minitest` run. |
| `rake test:unit` | The unit tier: zr's own internals (`test/unit`). |
| `rake test:programs` | The program tests: Ruby programs that zr builds, each checked against the pinned ruby (`test/programs_test.rb`). |
| `rake test:ext` | The C extensions that zr links, each checked against the pinned ruby (`test/ext`). |
| `rake lint` | Runs RuboCop with the cops that `.rubocop.yml` turns on. |
| `rake gen` | Writes every generated file again (`zr-dev gen all`). `CHECK=1 rake gen` writes nothing, and fails if a file is out of date. |

To run some tests, give their paths to `zr-dev test`:
`bin/zr-dev test test/unit/cli_test.rb`, `bin/zr-dev test --suite unit -n /blocks/`,
or `bin/zr-dev test test/programs/core/string`. Each run keeps the
time of each test in `tmp/zr-dev-test/times.tsv`; `bin/zr-dev test --slowest [N]`
prints the slowest of them, and runs nothing. `SLOW=1` gives a longer report at
the end of a run: `SLOW=1 bin/minitest test/unit/cli_test.rb`. `COVERAGE=1` measures the
line and branch coverage of `lib/` (not `lib/zr/runtime`, which zr
compiles and ruby does not run) with SimpleCov, and writes the report
to `tmp/coverage/index.html`. Give it paths: `COVERAGE=1 bin/minitest
test/unit/bytes_test.rb`. It gates nothing.

### Gem and release

| Task | Does |
|---|---|
| `rake release`, `rake gem:release` | Stop with a message: a release is a pushed `vX.Y.Z` tag, which the release workflow checks, builds and pushes. See [How to release zr](../how-to/release.md). |
| `rake gem:build` | Builds `pkg/zr-<version>.gem`. |
| `rake gem:install`, `rake gem:install:local` | Builds the gem and installs it. |
| `rake gem:build:checksum`, `rake gem:clean`, `rake gem:clobber` | Bundler's other gem tasks. |

`rake build` builds the runtime, not the gem. Bundler's `build`,
`install` and `release` tasks are under `gem:`.

## zr-dev

`zr-dev` holds the tools that work on a checkout. Run it with the ruby
of the checkout: `bin/zr-dev` in the checkout, or `ruby
<checkout>/tool/zr-dev.rb` from any directory.

```
$ bin/zr-dev help                 # every command
$ bin/zr-dev bench --help         # the options of one command
$ bin/zr-dev gems help            # the commands of a group
```

The tables below write `zr-dev` for `bin/zr-dev` (see
[The binstubs](#the-binstubs)). The code of
each command is in `tool/<command>.rb`, with `_` for `-`
(`tool/cruby_test.rb`). The header comment of each file
gives more examples.

### Tests

| Command | Does |
|---|---|
| `zr-dev test [options] [path[:line]...]` | Runs zr's tests with `bin/minitest`: every test, or the test files (with `:LINE` for one test), directories of test files, and programs or directories of programs, anywhere, that you give. `--suite`, `--changed [BASE]` (the tests that the diff against BASE, default `main`, reaches: `tool/lib/zr/dev/reach.rb`) and `--failed` select tests; `-n` and `-e` select by name; `--record`, `--verify` and `--live` say where a program's expected output comes from; `-j`, `--target`, `--gc-stress`, `--no-build`, `--no-cache`, `--fail-fast`, `--timeout` and `--seed` say how they run; `--slowest [N]` prints the slowest tests of the saved times. Each option sets the variable that `bin/minitest` reads, which works without zr-dev too. `--list` prints the command and the tests, and runs nothing. See [How to run the tests](../how-to/run-the-tests.md). |
| `zr-dev vendor` | Writes `vendor/` (the pinned ruby's own library from its source at `RUBY_REVISION`, the bundled gems and the port gems from their `.gem` files, prism's templates from its tag), `vendor/vendor.lock` and `lib/zr/library/stdlib.rb`, from `tool/lib/zr/dev/vendored.rb`, `lib/zr/library/ports.rb` and `lib/zr/ruby_version.rb`. It needs `RUBY_SRC` and `PRISM_SRC`. See [How to update the vendored code](../how-to/update-vendored-code.md). |
| `zr-dev vendor --check` | Checks each file of `vendor/` against the lock, offline. |
| `zr-dev vendor outdated` | Lists the gems of `vendor/` that have a newer release on rubygems.org. |
| `zr-dev vendor diff GEM [VERSION]` | Lists the files that change from the locked GEM to VERSION (default: the newest), and zr's files under `lib/zr/runtime/` that replace one of them. |

### Gems

[How to check a gem](../how-to/check-a-gem.md) tells more. A gem is `NAME`, `NAME=VERSION` or the path of an unpacked gem. `--corpus DIR` (or `ZR_GEM_CORPUS`) finds each gem first in `DIR/<name>`; `--offline` fetches nothing.

| Command | Does |
|---|---|
| `zr-dev gems try GEM [--keep] [--save] [--build-only]` | Fetches the gem and the gems that it needs (ruby platform only), builds a program that requires it, runs the program under the pinned ruby and as a zr binary, and prints the tier, the diff and the path of the log (`tmp/gems/logs`). `--keep` keeps the work directory. `--save` writes the row into `log/gems/compat.tsv`. `--build-only` builds the program and runs nothing. |
| `zr-dev gems sweep [GEM...] [--top N|FIRST..LAST] [--jobs N] [--save] [--build-only]` | Tries many gems, one line each, then counts the tiers. `--top N` adds the N most downloaded gems of `log/gems/top.tsv`, and `--top FIRST..LAST` those ranked FIRST to LAST. As each gem ends, its line goes into `log/gems/sweep-<time>.log` and its row into `log/gems/sweep-<time>.tsv`, and with `--save` into `log/gems/compat.tsv`. `--build-only` runs no gem code: it takes gems from rubygems.org only and stops after the build. |
| `zr-dev gems triage [KIND] [--file TSV]` | Groups the gems that do not load by the kind of failure, the kind that stops the most gems first. With `KIND`, it gives each gem of that kind with its detail. |
| `zr-dev gems top [--refresh] [--count N]` | Prints the most downloaded gems with their tiers. `--refresh` writes `log/gems/top.tsv` again from packages.ecosyste.ms. |

### C extensions

| Command | Does |
|---|---|
| `zr-dev ext imports [--all] <bundle-or-object>...` | Lists what a C extension takes from ruby that zr's C API (`lib/zr/runtime/kernel/capi/`) does not have yet: the ruby names among the undefined symbols of a bundle or an object file, read with zr's own Mach-O reader. `--all` lists every ruby import, `+` for those the C API has and `-` for the others. It fails when one is missing, as a build that links the extension refuses then. |
| `zr-dev ext rank [--top N] [--build] [--only NAME,...] [--store DIR]` | Ranks the C extensions that keep the top N gems of `log/gems/top.tsv` (1000) from zr: each `cext:<name>` kind of `log/gems/compat.tsv`, by the number of those gems that it blocks, then by its own gem's downloads. `--build` builds each one, one at a time and for at most 10 minutes, from the gem that `zr-dev gems` unpacked in `--store` (`tmp/gems`) with `Ext::Builder`, which runs the gem's `extconf.rb`: gem code that a sweep never runs. It prints what each one lacks of zr's C API, then the functions to add, each with the number of top gems that wait on it. |
| `zr-dev ext compare <gem>...` | Compares zr's port of a gem's C with the gem's real C extension: it builds each program of `test/programs/stdlib/<gem>/` both ways into `tmp/ext-compare/` (the native way with `--native-ext <gem> --gem <gem>=<newest installed version>`), runs each binary three times, and prints a table row for each gem: the programs, how many give ruby's output each way (checked as the program tests check it), the total of the fastest times, and the mean binary size. [Ports and native extensions](ports-vs-native.md) records its table. |

### Expected outputs

| Command | Does |
|---|---|
| `zr-dev expect [--all] [--check] [path...]` | Runs each program test or benchmark under the pinned ruby, in a run directory as the test does (a benchmark from the root), and writes its files beside it: `foo.rb.expected`, and `foo.rb.err.expected` and `foo.rb.status` when they are not empty and not `exit 0` (`tool/expect.rb`). On Linux, it writes `foo.rb.linux.expected` when the stdout is different. With no path, it takes `test/programs`. It writes only a test whose `foo.rb.expected` is missing or older than the program; `--all` writes each test. `--check` writes nothing, lists each test whose files differ from ruby, and fails if there is one. See [Program tests](program-tests.md#expected-output). |
| `zr-dev rubyspec <area>... \| --all [-f PATTERN] [-j JOBS] [--shard I/N] [--update-tags] [--keep]` | Runs ruby/spec under the pinned ruby and in zr binaries, and compares each example. See [ruby/spec and test-all](#rubyspec-and-test-all). |
| `zr-dev cruby-test <dir>... \| --all [-f PATTERN] [-j JOBS] [--shard I/N] [--update-tags] [--keep]` | Runs CRuby's test-all under the pinned ruby and in zr binaries, and compares each test. See [ruby/spec and test-all](#rubyspec-and-test-all). |

#### ruby/spec and test-all

`zr-dev rubyspec` runs ruby/spec from the CRuby checkout at `RUBY_SRC`
(at `Zr::RUBY_REVISION`). An area is a directory of `spec/ruby`, such
as `language` or `core/array`; `core` and `library` are each of their
directories, and `--all` is every area. `command_line`, `optional/capi`
and `security` are CRuby's alone.

The spec files go into binaries of 20 files, built one at a time; a
chunk that does not build is split until the file is alone. Each file
runs in its own process with a limit of 120 s, 2 at once. ruby's
results are kept by the file's digest in `log/rubyspec/ruby/`.

The examples that zr fails are tags in mspec's form in
`test/rubyspec/tags/`: `fails:`, `hangs:` (zr's run skips it),
`fails(build):` and `fails(load):`. `--update-tags` writes them from
the run. `test/unit/rubyspec_ratchet_test.rb` fails on an untagged gap
or a stale tag.

A run writes these files:

- `log/rubyspec/results/<area>.json`, the results;
- `log/rubyspec/<area>.txt`, a report of the gaps;
- `log/rubyspec/issues/<area>.jsonl`, a live list of the gaps;
- `log/rubyspec/tests/<area>.log`, the output of zr's runs line by
  line, with the time and the file. `tail -f` shows each example as it
  ends, and the one that hangs;
- `test/rubyspec/summary.tsv`, again.

`zr-dev cruby-test` runs a directory of CRuby's `test/` in `RUBY_SRC`,
such as `ruby` or `json`, on CRuby's own runner, and compares each
test in the same way. A test that starts a ruby (`assert_separately`,
`assert_in_out_err`) starts zr through `RUBY`, so a file has 600 s.
The tags are `test/cruby/tags/<dir>/<file>.txt`, a line for each test:
its name, a tab, and why (`fail`, `timeout` (zr's run skips it), or a
reason of your own such as `ractor`; `*` with `build` or `load` for
the file). `--update-tags` writes `fail` for a new gap, and keeps the
reason of a tag that stays. The results, the reports, the live gap lists
(`issues/<dir>.jsonl`) and the live test logs (`tests/<dir>.log`) are
in `log/cruby-test/`, and the summary is `test/cruby/summary.tsv`. The
ratchet is `test/unit/cruby_test_ratchet_test.rb`.

Only one suite runs at a time (`tmp/suite.lock`).

### Generated files

Each generator writes a file from the ruby that `.ruby-version` names,
or from a CRuby source at that ruby's revision. The file starts with a
header that tells this. Do not edit a generated file by hand. A
generator that reads a table from the running ruby stops on a ruby that
is not the pinned one: the same version, patch level and revision
(`Zr.pinned_ruby?`).

Every generator takes `--check`. With `--check`, it writes nothing, and
it fails if the file is out of date. `zr-dev gen all` runs every
generator in order (`rake gen` runs it too), but `openssl_constants`
(`test/unit/openssl_constants_test.rb` checks its rows) and
`gem-compat`. It skips, with a warning, a generator that reads another
OS's system library (`libsystem` runs only on macOS). `--except
NAME,...` leaves out more. CI runs `gen all --check`.

The generators read the CRuby source from the checkout that `RUBY_SRC`
names (default `tmp/ruby`), at `Zr::RUBY_REVISION` (`lib/zr/ruby_version.rb`). They read
prism from `PRISM_SRC` (default `tmp/prism`), at the commit that ruby
bundles (`Dev.prism_revision`). With no checkout there, a generator
stops and says to run `ruby .github/scripts/fetch_sources.rb`, which
fetches both. The code of each generator is
in `tool/gen/`.

| Command | Writes |
|---|---|
| `zr-dev gen ruby_version` | `lib/zr/ruby_version.rb` (`Zr::RUBY_PIN`, `Zr::RUBY`, `Zr::RUBY_REVISION`, `Zr::RUBY_API`, `Zr::RUBY_LIB_VERSION` and the rest) and `lib/zr/runtime/core/ruby_version.rb` (the `RUBY_*` constants that a program sees), from `.ruby-version` and the CRuby source at that tag in `RUBY_SRC`, never from the running ruby. It runs first: the other generators, `zr-dev vendor` and the gem read what it writes. To change the ruby, see [How to update the vendored code](../how-to/update-vendored-code.md#a-new-ruby). |
| `zr-dev gen features` | `lib/zr/hir/features.rb`: the names that `require` accepts |
| `zr-dev gen unicode` | `lib/zr/runtime/core/unicode.rb`: case mappings |
| `zr-dev gen encodings` | `lib/zr/runtime/core/encodings.rb`: the encoding registry |
| `zr-dev gen transcode` | `lib/zr/runtime/core/transcode.rb`: single-byte encoding tables |
| `zr-dev gen cjk` | `lib/zr/runtime/core/cjk.rb`: multibyte encoding tables |
| `zr-dev gen enc_mb` | `lib/zr/runtime/kernel/enc_mb.rb`: multibyte encoding descriptors |
| `zr-dev gen onig_unicode` | `lib/zr/runtime/core/regexp/unicode_tables.rb` and `lib/zr/runtime/kernel/onig_tables.rb`: Onigmo's Unicode tables, from CRuby's `enc/unicode` at `RUBY_SRC`. Both files come from one computed value; `test/unit/onig_unicode_test.rb` checks that they agree, and `gen all --check` that they are current. |
| `zr-dev gen onig_encodings` | `lib/zr/runtime/core/regexp/onig/encoding_tables.rb`: Onigmo's encodings past UTF-8, from CRuby's `enc/*.c` |
| `zr-dev gen nkf [--source PATH]` | `lib/zr/runtime/ext/nkf/tables.rb`: nkf's conversion tables, from `utf8tbl.c` of the nkf .gem that `vendor/vendor.lock` names (or `NKF_SRC`) |
| `zr-dev gen zlib_tables` | `lib/zr/runtime/kernel/zlib_tables.rb`: the tables that zlib 1.3.1 computes |
| `zr-dev gen openssl_constants` | `lib/zr/runtime/ext/openssl/ossl/constants.rb`: openssl's Integer constants. Not in `gen all`: the order comes from the host's OpenSSL build, so read the diff. |
| `zr-dev gen emoji` | `lib/zr/runtime/core/emoji.rb` |
| `zr-dev gen builtin_lines` | `lib/zr/runtime/core/builtin_lines.rb` |
| `zr-dev gen tables` | This OS's errno, fcntl, etc and socket tables, into `lib/zr/runtime/core/os/<os>/` and `lib/zr/runtime/ext/os/<os>/`. The socket table reads `ext/socket/mkconstants.rb` from `RUBY_SRC`. |
| `zr-dev gen gem-compat` | `docs/reference/gem-compat.md`: how far each gem gets with zr, from `log/gems/compat.tsv`. It runs no gem; `zr-dev gems sweep --save` writes the table. The table is not committed, so `gen all` leaves this page out, and without the table the command stops. |
| `zr-dev gen capi` | `docs/reference/c-api.md`: the functions and data of ruby's C API that the kernel gives C extensions, from `lib/zr/runtime/kernel/capi/*.rb` |
| `zr-dev gen support` | `docs/reference/support.md`: what zr refuses, from the compiler, and the baseline of each target |
| `zr-dev gen perf` | `docs/explanation/performance.md`: the run and build times, from the newest reports in `benchmark/results/` |
| `zr-dev gen redefinitions` | `lib/zr/runtime/core/redefinitions.rb`: the core methods whose redefinition makes ruby warn. It runs ruby for each core method, in parallel. |

#### Generated files that the unit tier tests

The unit tier writes these files again and compares them with the
committed files. The test of `builtin_lines` skips without a CRuby
checkout (`RUBY_SRC`). Thus a file that is out of date makes a test fail.

| Command | Writes | Tested by |
|---|---|---|
| `zr-dev gen libsystem` | `lib/zr/obj/macho/libsystem.rb` | `test/unit/libsystem_test.rb` |
| `zr-dev gen prism` | `lib/zr/runtime/ext/prism/ruby/*.rb`, from the templates in `tool/gen/prism/templates` | `test/unit/prism_test.rb` |
| `zr-dev gen prism_encoding_tables` | `lib/zr/runtime/ext/prism/ruby/encoding_tables.rb` | `test/unit/prism_test.rb` |
| `zr-dev gen builtin_lines` | `lib/zr/runtime/core/builtin_lines.rb` | `test/unit/builtin_lines_test.rb` |

`ZR_BLESS=1` on one of these tests writes its file again, in place of
the check. `ZR_BLESS=1` on `test/unit/libsystem_test.rb` writes the
libSystem list again. See
[How to run the tests](../how-to/run-the-tests.md#accept-a-new-snapshot).

### Measure

| Command | Does |
|---|---|
| `zr-dev bench [--runs N] [--target TRIPLE] [filter...]` | Builds each program in `benchmark/`, checks its output, and times it beside `ruby` and `ruby --yjit`. `--runs` sets the runs of each program (default 5). `--target` sets the target to build for. The words select benchmarks by name: `zr-dev bench --runs 5 fib`. |
| `zr-dev changelog VERSION` | Prints the body of the dated section of VERSION in `CHANGELOG.md`: the notes of its GitHub Release (`tool/changelog.rb`). It fails when the section is missing, has no date, or is empty. The release workflow writes the notes through `.github/scripts/release_notes.rb`, which also checks the tag against `Zr::VERSION`. |
| `zr-dev bench --check [before after]` | Compares the newest report with the one before it, and runs nothing. With two arguments, it compares those two reports, given as paths or revisions. |
| `zr-dev compile [--runs N] [--write] [--zr [--commit \| --check]] [filter...]` | Times how long zr takes to compile each rung of `benchmark/compile/`, phase by phase. `--runs` sets the builds of each rung, after one warmup (default 3). `--write` writes the table to `tmp/bench/compile.txt`. `--zr` also builds the compiled compiler with ruby (`tmp/compile/zr`), and times it. The words select rungs by name. |
| `zr-dev compile --zr --commit` | Also writes a baseline to `benchmark/results/compile/`. |
| `zr-dev compile --profile runtime\|eval` | Lowers the runtime or eval support object, then times the passes and the assembly of each function, one at a time. It prints the sums and the 20 slowest functions, and writes all of them to `tmp/bench/profile-<object>.tsv`. |
| `zr-dev compile --zr --check` | Fails if the compiled compiler is slower than the newest baseline in `benchmark/results/compile/`. |
| `zr-dev host <file.rb> [args...]` | Runs a program on CRuby with no build: the kernel runs as Ruby (`Machine::Host`), and a walker runs the core library, the gem prelude and the program over the kernel's heap (`Machine::Host::Walk`). The exit status is the program's. It is much slower than a binary. `ZR_TEST_HOST=1 bin/minitest test/programs_test.rb` runs the program tests this way. |
| `zr-dev fuzz run [--time 30m \| --count N] [-j N] [--seed S] [--mode gen,mutate,meta,junk,seed] [--packs a,b] [--seeds DIR,...] [--coverage] [--no-reduce] [--no-layer]` | Fuzzes zr: checks programs under the pinned ruby and as zr binaries until the time (default 30 minutes) or the count is up. `gen` writes typed programs from a seed, `mutate` edits the seeds (default `test/programs` and `log/fuzz/corpus`) on prism's tree, `meta` rewrites generated programs, `junk` breaks seeds, and `seed` runs each seed once as it is. Each difference is reduced, put in a bucket by its kind and key, run hosted to name the layer at fault (`kernel` or `compiler`), and kept in `log/fuzz/cases/<bucket>/` with ruby's expected output. `--coverage` keeps programs that reach new compiler lines as seeds. The run holds the suite lock and builds with a copy of zr (`tmp/suite/zr`), so the checkout can change. Ctrl-C stops it and writes the summary. |
| `zr-dev fuzz reduce <file.rb>` | Reduces any Ruby file that zr gets wrong to a small one that fails the same way, into `log/fuzz/reduced/`. |
| `zr-dev fuzz recheck [bucket...]` | Checks the smallest case of each open bucket again, and marks the ones that zr now passes as fixed. |
| `zr-dev fuzz replay <case id\|file.rb>` | Checks one case again, and prints the diff. |
| `zr-dev fuzz report [--all]` | Lists the open buckets by count, with the layer and the smallest case, and the compiler coverage by directory. |
| `zr-dev fuzz gen [--seed S] [--packs a,b] [--check N]` | Prints the program of a seed, or runs N programs on ruby alone, twice each, and reports how many end in time and give the same output, and which errors stop units most often. |
| `zr-dev golden save\|check [LABEL]` | Lowers the kernel on `aarch64-apple-darwin`, `aarch64-linux-musl` and `wasm32-wasi`, and writes (`save`) or compares (`check`) one line for each fact a build sees: each function's IR fingerprint, each datum, the raw functions, the kernel's description and the symbol names, in `tmp/golden/LABEL/` (default `base`). A change to the kernel's spelling must keep it the same. |

See [How to measure performance](../how-to/measure-performance.md).

### Self-compile checks

| Command | Does |
|---|---|
| `zr-dev stage 1` | Builds the compiler (`exe/zr`) with ruby into `tmp/stage1/zr`, and passes if the build has no refusal. It keeps the binary, and uses it again while `exe`, `lib`, `vendor` and `Gemfile.lock` are the committed trees that it was built from. |
| `zr-dev stage 2` | Builds `exe/zr` with ruby (or uses stage 1's kept binary), then builds it again with that binary (`tmp/stage1/zr build exe/zr`) into `tmp/stage2/zr`, and compares the two binaries. Both binaries stay. It takes about ten minutes and 5 GB of memory. |

See [Bootstrapping](../explanation/bootstrapping.md).

### Build server

| Command | Does |
|---|---|
| `zr-dev serve [--idle MINUTES] [--socket PATH]` | Keeps one warm compiler for the edit loop, which each `zr run` and `zr build` of this checkout uses while it runs. |

The server holds the compiler loaded, YJIT warm, and the runtime's
description, symbols and prelinked images in memory. It forks one child
for each build. The client then runs the program itself, so the program
keeps the terminal, the signals and the exit status. A Ctrl-C in the
client stops the build. The server starts again when a file of zr that
it loaded changes, and stops after `--idle` minutes with no request
(default 30). It listens at `<cache>/server.sock`. `ZR_SERVER=0` makes
a command build alone, and `ZR_SERVER=PATH` uses the server at `PATH`.

On 2026-09-29, after an edit to a core file, `zr run` of hello took
4.2 s with the server and 4.9 s without it; after an edit to a
program, 0.23 s against 0.25 s (hello) and 0.40 s against 0.46 s (a
program with eval). The server held about 700 MB.

## The binstubs

`bin/zr` and `bin/zr-dev` are binstubs, as the gems' binstubs in `bin/`
are: each one loads its Ruby entry point (`exe/zr`, `tool/zr-dev.rb`)
under the ruby that runs it. Nothing is compiled first.
