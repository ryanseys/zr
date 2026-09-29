# Tools

A checkout has three scripts in `bin/`, a small set of rake tasks, and
the `zr-dev` tool. The rake tasks build, test, lint, generate and
release. The other maintainer tools are `zr-dev` commands.

For the `zr` command itself, see [The `zr` command](cli.md). For the
steps to run the tests, see [How to run the tests](../how-to/run-the-tests.md).

## Scripts

| Script | Does |
|---|---|
| `bin/setup` | Installs the gems (`bundle install`) and builds the runtime for this host (`rake build`). It tells you if wasmtime is not installed. |
| `bin/test [paths] [minitest options]` | Runs the tests. With no paths, it runs `test/unit`, then `test/spec`, then `test/e2e`. It builds the runtime first if the runtime is not built. |
| `bin/test --changed [--base REVISION]` | Runs the tests that the change against `main` (or `--base`) can reach, as `zr-dev affected` finds them. |
| `bin/console` | Starts IRB with zr loaded. |

A `bin/test` path can be a directory, a file, or a bare file name that
zr finds below `test/` (`bin/test cli_test.rb`). The words up to the
first word that starts with `-` are paths. The words after it go to
minitest (`bin/test test/spec -n /blocks/`). Each tier runs in its own
process.

`bin/test` reads these environment variables. `rake test` and the tier
tasks read them too, because they call `bin/test`.

| Variable | Effect |
|---|---|
| `TARGET=<triple>` | Builds and runs the programs for that target (sets `ZR_TARGET`). |
| `GC=stress` | Collects at every allocation (sets `ZR_GC_STRESS=1`). |
| `SLOW=1` | Also reports the 25 slowest files and the 20 slowest examples. `SLOW=<n>` with `n` > 1 reports `n` examples. |
| `N=<pattern>` | Runs only the examples whose name matches (minitest `-n`). |
| `X=<pattern>` | Leaves out the examples whose name matches (minitest `-e`). |
| `A="<options>"` | Gives other options to minitest. |
| `MT_CPU=<n>` | The number of worker processes. The default is one for each 2 GB of memory, with a quarter of the memory (at least 4 GB) and two cores kept free. |

All the test variables are in
[Environment variables](environment-variables.md#for-the-tests).

## Rake

`rake -T` lists every task. The `Rakefile` loads the bundle, so
`rake <task>` needs no `bundle exec`. The rake tasks take no paths and
no arguments. Give paths and minitest options to `bin/test`.

### Build

| Task | Does |
|---|---|
| `rake build` | Builds the runtime for this host: the runtime object, the prelinked image and eval support. `bin/test` also does this when the runtime is not built. |
| `rake build:wasm` | Builds the runtime for `wasm32-wasi`. |
| `rake build:all` | Builds the runtime for this host and for `wasm32-wasi`. |
| `rake build:self` | Builds the compiled compiler, `bin/zr`. `exe/zr` then uses it until a file under `lib`, `runtime`, `vendor` or the library tree changes (see `ZR_COMPILED`). |
| `rake build:tools` | Compiles the `zr-dev` tools with zr, to `bin/zr-dev`. See [The compiled tools](#the-compiled-tools). |

### Test, lint and generate

| Task | Does |
|---|---|
| `rake` | `rake lint`, then `rake test`. |
| `rake test` | The three tiers: unit, spec, e2e. |
| `rake test:unit` | The unit tier: zr's own internals (`test/unit`). |
| `rake test:spec` | The spec tier: Ruby specs, each checked against ruby 4.0.7 (`test/spec`). |
| `rake test:e2e` | The e2e tier: whole programs, built and linked, checked against ruby 4.0.7 (`test/e2e`). |
| `rake lint` | Runs RuboCop's Lint cops (`.rubocop.yml`). |
| `rake gen` | Writes every generated file again (`zr-dev gen all`). `CHECK=1 rake gen` writes nothing, and fails if a file is out of date. |

To run some test files, give their paths to `bin/test`:
`bin/test test/unit/cli_test.rb`, or `bin/test test/spec -n /blocks/`.
For the report of the slowest files and examples, set `SLOW=1`:
`SLOW=1 rake test:unit`, or `SLOW=1 bin/test test/spec/core/string`.

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
$ ruby tool/zr-dev.rb spec help            # the commands of a group
```

The tables below write `zr-dev` for `ruby tool/zr-dev.rb`. The code of
each command is in `tool/<command>.rb`. The header comment of each file
gives more examples.

### Tests

| Command | Does |
|---|---|
| `zr-dev affected [--base REVISION] [--dry-run]` | Runs the tests that a change can reach, with `bin/test` (the same as `bin/test --changed`). It reads the diff against `main`, or against `--base`. If the change can reach everything (the compiler, the kernel, the test support), it runs nothing and says so. `--dry-run` prints the test paths and runs nothing. |
| `zr-dev progress` | Prints the progress of the tier that runs now, or of the last tier (`tmp/test-progress.txt`). |

### Specs and recordings

| Command | Does |
|---|---|
| `zr-dev oracle [path...] [-n PATTERN]` | Runs the program of each spec example under ruby 4.0.7 and checks the example's expected output against it. It compiles nothing. A path selects one area or file (`zr-dev oracle test/spec/core/string`). `-n` selects the examples whose name matches. |
| `zr-dev record [--again] <program>...` | Runs a whole program under ruby 4.0.7 and writes its recording (`.out`, `.err`, `.status`) beside it. It does not change a program that has a recording. `--again` writes the recording again. |
| `zr-dev rubyspec <area>... [-f PATTERN] [-j JOBS] [--keep]` | Runs ruby/spec from the CRuby checkout at `RUBY_SRC` (at `Zr::RUBY_REVISION`) under ruby 4.0.7 and in a zr binary, one spec file per process with a limit of 60 s, and lists each example that passes in ruby and fails in the binary. An area is a directory of `spec/ruby`, such as `language` or `core/array`; `core` and `library` are each of their directories. `-f` selects the spec files whose path matches. The report of each area is in `tmp/rubyspec/<area>.txt`, and `tmp/rubyspec/summary.tsv` has a line for each area. |
| `zr-dev spec ask <spec file> <program.rb> [-n SENTENCE]` | Runs a candidate program under ruby, as `zr-dev oracle` does, and prints the `must_answer` assertion to paste. `-n` uses the keywords of an existing example. |
| `zr-dev spec check [path...]` | Checks the format rules of spec files: line length, heredoc tags, trailing spaces, duplicate sentences. With no path, it checks `test/spec`. |
| `zr-dev spec tidy [path...]` | Fixes what `spec check` reports, where the fix is safe. |
| `zr-dev spec verify [REVISION] [--renames] [path...]` | Compares each example with the same example at `REVISION` (default `HEAD`): its sentence, program, keywords and expected output. `--renames` lets the sentences change. `zr-dev spec verify main test/spec/core` checks one area. |
| `zr-dev spec fingerprint [path...]` | Prints a digest for each example, to compare before and after a change (`zr-dev spec fingerprint > before.txt`). |
| `zr-dev spec split [path...]` | Lists the bundled examples that can be split, and how. |
| `zr-dev spec dispatch [class...]` | Prints the programs that show which of its own methods a core class calls. It writes nothing: compare the output with the spec example. |

### Generated files

Each generator writes a file from ruby 4.0.7, or from a CRuby source at
the revision of ruby 4.0.7. The file starts with a header that tells
this. Do not edit a generated file by hand. A generator that reads a
table from the running ruby stops on a ruby that is not 4.0.7.

Every generator takes `--check`. With `--check`, it writes nothing, and
it fails if the file is out of date. `zr-dev gen all` runs every
generator in order (`rake gen` runs it too).

The generators read the CRuby source from the checkout that `RUBY_SRC`
names (default `~/dev/github.com/ruby/ruby`), at `Zr::RUBY_REVISION`
(`lib/zr/version.rb`). They read prism from `PRISM_SRC` (default
`~/dev/prism`, else `tmp/prism-1.9.0`). The code of each generator is
in `tool/gen/`.

| Command | Writes |
|---|---|
| `zr-dev gen features` | `lib/zr/hir/features.rb`: the names that `require` accepts |
| `zr-dev gen libraries` | `lib/zr/library_digests.rb`: the SHA-256 digests of the pinned gems' files |
| `zr-dev gen unicode` | `runtime/core/unicode.rb`: case mappings |
| `zr-dev gen encodings` | `runtime/core/encodings.rb`: the encoding registry |
| `zr-dev gen transcode` | `runtime/core/transcode.rb`: single-byte encoding tables |
| `zr-dev gen cjk` | `runtime/core/cjk.rb`: multibyte encoding tables |
| `zr-dev gen enc_mb` | `runtime/kernel/enc_mb.rb`: multibyte encoding descriptors |
| `zr-dev gen onig_unicode` | `runtime/core/regexp/unicode_tables.rb` and `runtime/kernel/onig_tables.rb`: Onigmo's Unicode tables, from CRuby's `enc/unicode` at `RUBY_SRC`. Both files come from one computed value; `test/unit/onig_unicode_test.rb` checks that they agree. |
| `zr-dev gen onig_encodings` | `runtime/core/regexp/onig/encoding_tables.rb`: Onigmo's encodings past UTF-8, from CRuby's `enc/*.c` |
| `zr-dev gen nkf [--source PATH]` | `runtime/ext/nkf/tables.rb`: nkf's conversion tables, from the installed nkf gem's `utf8tbl.c` (or `NKF_SRC`) |
| `zr-dev gen zlib_tables` | `runtime/kernel/zlib_tables.rb`: the tables that zlib 1.3.1 computes |
| `zr-dev gen openssl_constants` | `runtime/ext/openssl/ossl/constants.rb`: openssl's Integer constants. Not in `gen all`: the order comes from the host's OpenSSL build, so read the diff. |
| `zr-dev gen emoji` | `runtime/core/emoji.rb` |
| `zr-dev gen builtin_lines` | `runtime/core/builtin_lines.rb` |
| `zr-dev gen tables` | This OS's errno, fcntl, etc and socket tables, into `runtime/core/os/<os>/` and `runtime/ext/os/<os>/`. The socket table reads `ext/socket/mkconstants.rb` from `RUBY_SRC`, or from the copy that `MKCONSTANTS` names. |

#### Generated files that the unit tier tests

The unit tier writes these four files again and compares them with the
committed files. Thus a file that is out of date makes a test fail.

| Command | Writes | Tested by |
|---|---|---|
| `zr-dev gen description [--target TRIPLE]` | `runtime/ext/os/<os>/zr_description.rb`. With no `--target`, it writes every OS layer. With `--target`, it writes the layer of that target. | `test/unit/description_test.rb` |
| `zr-dev gen libsystem` | `lib/zr/obj/macho/libsystem.rb` | `test/unit/libsystem_test.rb` |
| `zr-dev gen prism` | `runtime/ext/prism/ruby/*.rb`, from the templates in `tool/gen/prism/templates` | `test/unit/prism_test.rb` |
| `zr-dev gen prism_encoding_tables` | `runtime/ext/prism/ruby/encoding_tables.rb` | `test/unit/prism_test.rb` |

`ZR_BLESS=1 bin/test test/unit/description_test.rb` also writes the
descriptions again. `ZR_BLESS=1` on `test/unit/libsystem_test.rb`
writes the libSystem list again. See
[How to run the tests](../how-to/run-the-tests.md#accept-a-new-snapshot).

### Measure

| Command | Does |
|---|---|
| `zr-dev bench [--runs N] [--target TRIPLE] [filter...]` | Builds each program in `benchmark/`, checks its output, and times it beside `ruby` and `ruby --yjit`. `--runs` sets the runs of each program (default 5). `--target` sets the target to build for. The words select benchmarks by name: `zr-dev bench --runs 5 fib`. |
| `zr-dev bench --check [before after]` | Compares the newest report with the one before it, and runs nothing. With two arguments, it compares those two reports, given as paths or revisions. |
| `zr-dev compile [--runs N] [--write] [--zr [--commit \| --check]] [filter...]` | Times how long zr takes to compile each rung of `benchmark/compile/`, phase by phase. `--runs` sets the builds of each rung, after one warmup (default 3). `--write` writes the table to `tmp/bench/compile.txt`. `--zr` also times the compiled compiler. The words select rungs by name. |
| `zr-dev compile --zr --commit` | Also writes a baseline to `benchmark/results/compile/`. |
| `zr-dev compile --profile runtime\|eval` | Lowers the runtime or eval support object, then times the passes and the assembly of each function, one at a time. It prints the sums and the 20 slowest functions, and writes all of them to `tmp/bench/profile-<object>.tsv`. |
| `zr-dev compile --zr --check` | Fails if the compiled compiler is slower than the newest baseline in `benchmark/results/compile/`. |
| `zr-dev probe [-j JOBS] <file.rb\|dir>...` | Runs each Ruby file under ruby 4.0.7 and as a zr binary, and prints a unified diff of each part that differs: stdout, stderr, the exit status and the signal. It compiles each file in a fork of one process that has the compiler and the runtime loaded. A directory means its `.rb` files. `-j` sets the probes at a time (default 4). |
| `zr-dev edit [--kind KIND,...] [--program NAME,...] [--runs N] [--commit]` | Times `zr run` right after an edit to zr, phase by phase. It works in a copy of the tree with its own cache (`tmp/edit/`), appends a new comment or method to one file for each kind, and puts the file back. The kinds are `none`, `kernel-comment`, `core-comment`, `core-method`, `lower-comment` and `ext-comment`; the programs are `hello` and `eval`. `--commit` writes the table to `benchmark/results/edit/`. |
| `zr-dev codesize [--all] [--against FILE]` | Counts the instructions the backend writes for the runtime: the total and the 20 largest functions. `--all` lists every function. `--against` compares with the file of an earlier run. |

See [How to measure performance](../how-to/measure-performance.md).

### Self-compile checks

| Command | Does |
|---|---|
| `zr-dev stage 1` | Compiles the compiler (`exe/zr`) two times, in two processes with two caches, and compares the compiler objects and the runtime objects byte for byte. |
| `zr-dev stage 2` | Builds `exe/zr` with ruby, then builds it again with that binary (`tmp/stage1/zr build exe/zr`), and compares the two binaries. It takes about ten minutes and 5 GB of memory. |
| `zr-dev repro [--wasm]` | Builds one program from two copies of the tree at two paths, with a different home, time zone, locale and job count, and one `--path-root`. It compares the binaries and the objects. `--wasm` also builds and compares the WASI modules. |

See [Bootstrapping](../explanation/bootstrapping.md).

### Cache

| Command | Does |
|---|---|
| `zr-dev cache size` | Shows the size of the cache, by kind of file. |
| `zr-dev cache live` | Lists the cache files of this checkout, and whether each is built. |
| `zr-dev cache prune [--days N]` | Deletes all cache files that this checkout does not use and that are older than one day (`ZR_CACHE_DAYS`). `--days 3` keeps files used in the last 3 days. |
| `zr-dev cache clear` | Deletes all the cache, also the files of this checkout. |

### Build server

| Command | Does |
|---|---|
| `zr-dev serve [--idle MINUTES] [--socket PATH]` | Keeps one warm compiler for the edit loop: the compiler loaded, YJIT warm, and the runtime's description, symbols and prelinked images in memory. While it runs, each `zr run` and `zr build` of this checkout sends it the build. The server forks one child for each build. The client then runs the program itself, so the program keeps the terminal, the signals and the exit status. A Ctrl-C in the client stops the build. The server starts again when a file of zr that it loaded changes, and stops after `--idle` minutes with no request (default 30). It listens at `<cache>/server.sock`. `ZR_SERVER=0` makes a command build alone, and `ZR_SERVER=PATH` uses the server at `PATH`. After an edit to a core file, `zr run` of hello took 4.2 s with the server and 4.9 s without it. After an edit to a program, it took 0.23 s against 0.25 s (hello) and 0.40 s against 0.46 s (a program with eval). The server holds about 700 MB. |

### Platform gem

| Command | Does |
|---|---|
| `zr-dev gem native [--install DIR]` | Builds `pkg/zr-<version>-<platform>.gem` for this host's platform, with `bin/zr` and its manifest in `exe/<platform>/`. Run `rake build:self` first. `--install DIR` installs the gem there and builds a program with the installed zr. |

See [How to release zr](../how-to/release.md).

## The compiled tools

`rake build:tools` compiles `tool/zr-dev.rb` with zr, to `bin/zr-dev`.
The binary runs the same commands as `ruby tool/zr-dev.rb`, and gives
the same output. It is a test of zr: the tools are ordinary Ruby, and zr
must compile them. git ignores `bin/zr`, `bin/zr-dev` and their
manifests.

- **A stale binary runs nothing.** The binary holds a copy of `lib/zr`.
  When a file under `lib`, `runtime`, `vendor`, `tool` or
  `test/support` changes, the binary gives the command to
  `ruby tool/zr-dev.rb`. Run `rake build:tools` again to use the binary.
- **Some commands run under ruby.** A generator that reads the running
  ruby's own tables, the oracle, `record` and the `spec` commands that
  ask ruby are `host_ruby!` commands. The binary gives them to ruby.
- **Run it outside `bundle exec`.** A zr binary reads `RUBYOPT` as ruby
  does, and bundler's setup does not run in a zr binary.
