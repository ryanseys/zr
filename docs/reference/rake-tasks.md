# Rake tasks and scripts

A checkout has three scripts in `bin/` and a set of rake tasks.
`rake -T` lists every task. The body of each task is in
`rakelib/*.rake`, and the header comment of each file gives its full
usage. The `Rakefile` loads the bundle, so `rake <task>` needs no
`bundle exec`.

For the `zr` command itself, see [The `zr` command](cli.md). For the
steps to run the tests, see [How to run the tests](../how-to/run-the-tests.md).

## Scripts

| Script | Does |
|---|---|
| `bin/setup` | Installs the gems (`bundle install`) and builds the runtime for this host (`rake build`). It tells you if wasmtime is not installed. |
| `bin/test [paths] [minitest options]` | Runs the tests. With no paths, it runs `test/unit`, then `test/spec`, then `test/e2e`. It builds the runtime first if the runtime is not built. |
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
| `MT_CPU=<n>` | The number of worker processes. |

All the test variables are in
[Environment variables](environment-variables.md#for-the-tests).

## Build

| Task | Does |
|---|---|
| `rake build` | Builds the runtime for this host: the runtime object, the prelinked image and eval support. `bin/test` also does this when the runtime is not built. |
| `rake build:wasm` | Builds the runtime for `wasm32-wasi`. |
| `rake build:all` | Builds the runtime for this host and for `wasm32-wasi`. |
| `rake build:self` | Builds the compiled compiler. `exe/zr` then uses it until a file under `lib`, `runtime`, `vendor` or the library tree changes (see `ZR_COMPILED`). |

## Tests

| Task | Does |
|---|---|
| `rake` | `rake lint`, then `rake test`. |
| `rake test` | The three tiers: unit, spec, e2e. |
| `rake test <paths>` | Only the given test files or directories, for example `rake test test/unit/cli_test.rb` or `rake test prism_test.rb`. |
| `rake test:unit` | The unit tier: zr's own internals (`test/unit`). |
| `rake test:spec` | The spec tier: Ruby specs, each checked against ruby 4.0.6 (`test/spec`). |
| `rake test:e2e` | The e2e tier: whole programs, built and linked, checked against ruby 4.0.6 (`test/e2e`). |
| `rake test:unit:slow`, `rake test:spec:slow`, `rake test:e2e:slow` | The tier, with the report of `SLOW=1`. |
| `rake test:progress` | Prints the progress of the tier that runs now, or of the last tier (`tmp/test-progress.txt`). |
| `rake affected` | Runs the specs that a change can reach. It reads the diff against `main`, or against `BASE=<revision>`. If the change can reach everything (the compiler, the kernel, the test support), it runs all the specs. |
| `rake lint` | Runs RuboCop's Lint cops (`.rubocop.yml`). |

## Specs and recordings

| Task | Does |
|---|---|
| `rake oracle` | Runs the program of each spec example under ruby 4.0.6 and checks the example's expected output against it. It compiles nothing. |
| `rake 'oracle[<path>]'` | The same for one area or file, for example `rake 'oracle[test/spec/core/string]'`. |
| `rake 'record[<program>]'` | Runs a whole program under ruby 4.0.6 and writes its recording (`.out`, `.err`, `.status`) beside it. It does not change a program that has a recording. |
| `rake 'record[--again <program>]'` | Writes the recording again. |
| `rake 'spec:ask[<spec file> <program.rb>]'` | Runs a candidate program under ruby, as `rake oracle` does, and prints the `must_answer` assertion to paste. `-n "<sentence>"` uses the keywords of an existing example. |
| `rake 'spec:check[<path>]'` | Checks the format rules of spec files: line length, heredoc tags, trailing spaces, duplicate sentences. |
| `rake 'spec:tidy[<path>]'` | Fixes what `spec:check` reports, where the fix is safe. |
| `rake 'spec:verify[<revision>]'` | Compares each example with the same example at `<revision>`: its sentence, program, keywords and expected output. `'[HEAD --renames]'` lets the sentences change. `'[main test/spec/core]'` checks one area. |
| `rake spec:fingerprint` | Prints a digest for each example, to compare before and after a change (`rake spec:fingerprint > before.txt`). |
| `rake 'spec:split[<path>]'` | Lists the bundled examples that can be split, and how. |

## Bootstrap and reproducibility

| Task | Does |
|---|---|
| `rake stage1` | Compiles the compiler (`exe/zr`) twice, in two processes with two caches, and compares the compiler objects and the runtime objects byte for byte. |
| `rake stage2` | Builds `exe/zr` with ruby, then builds it again with that binary (`tmp/stage1/zr build exe/zr`), and compares the two binaries. It takes about ten minutes and 5 GB of memory. |
| `rake repro` | Builds one program from two copies of the tree at two paths, with a different home, time zone, locale and job count, and one `--path-root`. It compares the binaries and the objects. |
| `rake repro[wasm]` | The same, and it also compares the WASI modules. |

See [Bootstrapping](../explanation/bootstrapping.md).

## Performance

| Task | Does |
|---|---|
| `rake bench` | Builds each program in `benchmark/`, checks its output, and times it beside `ruby` and `ruby --yjit`. |
| `rake 'bench[<options and names>]'` | `--runs <n>` (default 5), `--target <triple>`, and words that select benchmarks by name: `rake 'bench[--runs 5 fib]'`. |
| `rake bench:check` | Compares the newest report with the one before it. `rake 'bench:check[<before> <after>]'` compares two reports, given as paths or revisions. |
| `rake compile` | Times how long zr takes to compile each rung of `benchmark/compile/`, phase by phase (three runs each). |
| `rake 'compile[<options and names>]'` | `--runs <n>`, `--write` (writes `tmp/bench/compile.txt`), `--zr` (also times the compiled compiler), and words that select rungs by name. |
| `rake codesize` | Counts the instructions the backend writes for the runtime: the total and the 20 largest functions. `'codesize[--all]'` lists every function. `'codesize[<file.tsv>]'` compares with an earlier run. |

See [How to measure performance](../how-to/measure-performance.md).

## Cache

| Task | Does |
|---|---|
| `rake cache:size` | Shows the size of the cache, by kind of file. |
| `rake cache:live` | Lists the cache files of this checkout, and whether each is built. |
| `rake cache:prune` | Deletes all cache files that this checkout does not use and that are older than one day (`ZR_CACHE_DAYS`). `rake 'cache:prune[3]'` keeps files used in the last 3 days. |
| `rake cache:clear` | Deletes all the cache, also the files of this checkout. |

## Generated files

Each task writes a file from ruby 4.0.6, or from a CRuby source at the
revision of ruby 4.0.6. The file starts with a header that tells this.
Do not edit a generated file by hand. A task that reads a table from
the running ruby stops on a ruby that is not 4.0.6.

| Task | Writes |
|---|---|
| `rake gen:features` | `lib/zr/hir/features.rb` |
| `rake gen:libraries` | `lib/zr/library_digests.rb`: the SHA-256 digests of the pinned gems' files |
| `rake gen:unicode` | `runtime/core/unicode.rb`: case mappings |
| `rake gen:encodings` | `runtime/core/encodings.rb`: the encoding registry |
| `rake gen:transcode` | `runtime/core/transcode.rb`: single-byte encoding tables |
| `rake gen:cjk` | `runtime/core/cjk.rb`: multibyte encoding tables |
| `rake gen:enc_mb` | `runtime/kernel/enc_mb.rb`: multibyte encoding descriptors |
| `rake gen:emoji` | `runtime/core/emoji.rb` |
| `rake gen:builtin_lines` | `runtime/core/builtin_lines.rb` |
| `MKCONSTANTS=<ruby source>/ext/socket/mkconstants.rb rake tables` | This OS's errno, fcntl, etc and socket tables, into `runtime/core/os/<os>/` and `runtime/ext/os/<os>/`. It fails if the result is different from the committed files. |
| `rake 'gen:dispatch[<classes>]'` | Prints the programs that show which of its own methods a core class calls. It writes nothing: compare the output with the spec example. |

### Generated files that the unit tier tests

The unit tier writes these four files again and compares them with the
committed files. Thus a file that is out of date makes a test fail.
The generators are in `test/support/generators/`.

| Task | Writes | Tested by |
|---|---|---|
| `rake gen:description` (`'gen:description[wasm32-wasi]'` for another target) | `runtime/ext/os/<os>/zr_description.rb` | `test/unit/description_test.rb` |
| `rake gen:libsystem` | `lib/zr/obj/macho/libsystem.rb` | `test/unit/libsystem_test.rb` |
| `rake gen:prism_generate` | `runtime/ext/prism/ruby/*.rb` | `test/unit/prism_test.rb` |
| `rake gen:prism_encoding_tables` | `runtime/ext/prism/ruby/encoding_tables.rb` | `test/unit/prism_test.rb` |

`ZR_BLESS=1 bin/test test/unit/description_test.rb` also writes the
descriptions again. See
[How to run the tests](../how-to/run-the-tests.md#accept-a-new-snapshot).

### Tables without a generator

These tables come from sources that do not change. Their generators
are not in the repository; `git log` finds them.

| File | Source |
|---|---|
| `runtime/ext/nkf/tables.rb` | nkf 0.3.0's `utf8tbl.c` |
| `runtime/core/regexp/unicode_tables.rb`, `runtime/kernel/onig_tables.rb` | ruby 4.0.6's `enc/unicode/17.0.0` headers |
| `runtime/core/regexp/onig/encoding_tables.rb` | CRuby 4.0.6's `enc/*.c` |
| `runtime/kernel/zlib_tables.rb` | zlib's `crc32.c` and `trees.c` |
| `runtime/ext/openssl/ossl/constants.rb` | the openssl 4.0.2 gem of ruby 4.0.6 |

## Gem and release

| Task | Does |
|---|---|
| `rake release` | Builds the gem, tags the version and pushes the gem to rubygems.org. The release workflow runs it. |
| `rake gem:build` | Builds `pkg/zr-<version>.gem`. |
| `rake gem:install`, `rake gem:install:local` | Builds the gem and installs it. |
| `rake gem:build:checksum`, `rake gem:clean`, `rake gem:clobber` | Bundler's other gem tasks. |

`rake build` builds the runtime, not the gem. Bundler's `build`,
`install` and `release` tasks are under `gem:`.
