# How to run the tests

This guide shows you how to run zr's tests in a checkout. Run the
smallest set of tests that covers your change. Run all the tests before
you open a pull request.

For the full list of rake tasks, `zr-dev` commands and test variables,
see [Tools](../reference/tools.md). This guide writes `zr-dev` for
`ruby tool/zr-dev.rb`. To learn how a
tier runs, see [How the tests run](../explanation/how-the-tests-run.md).

## Before you start

Set up the checkout one time:

```console
$ bin/setup
```

`bin/setup` installs the gems and builds the runtime for this host.
The first build takes a few minutes. `bin/minitest` builds the runtime
again when a change under `lib/` or `lib/zr/runtime/` makes it out of date.
To build the runtime without a test run:

```console
$ rake build
```

The WASI runtime is a different build, of about five minutes. Build it
before you run the tests that make WASI modules:

```console
$ rake build:wasm
$ rake build:all        # this host and wasm32-wasi; needs about 12 GB of memory
```

Until you build it, the unit tests that make WASI modules skip, and
tell you why. They also skip when wasmtime is not installed.

## Run all the tests

```console
$ bin/minitest
```

This runs every `test/**/*_test.rb` file: the unit tests and the
program tests. `rake test` runs the two tiers, one after the other.
`rake` runs `rake lint` first, then the tests. To time a run, use the
shell's `time`:

```console
$ time bin/minitest test/unit
```

## Run one tier or one file

Give `bin/minitest` one or more paths:

```console
$ bin/minitest test/unit
$ bin/minitest test/programs_test.rb
$ bin/minitest test/unit/wasm_test.rb test/unit/exe_test.rb
```

`rake test:unit` and `rake test:programs` run one tier.

## Run some program tests

`test/programs_test.rb` has one test for each program below
`test/programs` that has a `.rb.expected` file. To run some of them,
set `ZR_PROGRAMS` to paths below `test/programs`, separated by commas.
Each path is a directory or one program:

```console
$ ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
$ ZR_PROGRAMS=core/gc,lang bin/minitest test/programs_test.rb
$ ZR_PROGRAMS=core/string/blocks/lambda_arrow_string_return.rb bin/minitest test/programs_test.rb
```

The name of each test is `test_<path below test/programs>`, so a
minitest option also selects programs by name:

```console
$ bin/minitest test/programs_test.rb -i /stdlib.uri/
```

## Run some unit tests

Put minitest options after the paths: `-i` (or `-n`) selects tests by
name, `-e` excludes tests by name, `-s` sets the seed and `-v` shows
each test:

```console
$ bin/minitest test/unit -i /deduplicated/
$ bin/minitest test/unit -i '/Hygiene|Exe|Target/'
$ bin/minitest test/unit/cli_test.rb -e /encoding/
```

To run the test at one line, give the line after the path:

```console
$ bin/minitest test/unit/cli_test.rb:214
```

When a run fails, minitest prints each failure. A failed program test
shows the diff against ruby's output. When zr does not build or run
the program, the test is an error. A skip tells you why: a baseline
entry or a need that the host does not meet. To run one program test
again, give its path to `ZR_PROGRAMS`. See
[Program tests](../reference/program-tests.md#results).

## Run the tests that a change can reach

```console
$ bin/zr-dev affected
$ bin/zr-dev affected --base origin/main
$ bin/zr-dev affected --dry-run
```

`zr-dev affected` reads the diff against `main`, or against
`--base`, and runs the tests that the changed files can reach. A
changed unit test file runs itself, and a changed program, or a file
beside it, runs the program. For a file under `lib/zr/runtime/core`, these
are the directory of its class and every program test that uses the
class name. For a file under `lib/zr` that does not change what a
build writes, these are the unit tests that load it, and
`test/programs/cli` when `exe/zr` loads it. A change to the compiler, the kernel or the test support reaches
every test: then `zr-dev affected` runs nothing and tells you so,
because a full run is a decision for you. It runs the tests that it
finds with `bin/minitest`: the unit test files by path, and the program
tests through `ZR_PROGRAMS`. `--dry-run` prints the paths and runs
nothing.

## Use fewer workers

`bin/minitest` runs one worker process for each 2 GB of memory. It keeps a
quarter of the memory (at least 4 GB) and two cores free, and prints
the number when it starts. A 16 GB, 12-core Mac gets 6 workers. If the
machine is slow or swaps during a run, set fewer:

```console
$ MT_CPU=4 ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
```

Do not run two tiers or two `bin/minitest` commands at the same time.
Each one takes its workers from the same memory.

## Stop at the first failure, or change the time limits

`ZR_TEST_FAIL_FAST=1` runs no more tests after one fails.
`ZR_TEST_SECONDS=N` sets the time limit of each program run and build
(default 60 s). A worker also stops a test after `ZR_TEST_TIMEOUT`
seconds (default 180); `ZR_TEST_TIMEOUT=0` removes that limit:

```console
$ ZR_TEST_FAIL_FAST=1 bin/minitest test/unit
$ ZR_TEST_SECONDS=300 ZR_TEST_TIMEOUT=0 ZR_PROGRAMS=stdlib bin/minitest test/programs_test.rb
```

## Run the program tests on the host

`ZR_TEST_HOST=1` runs the program tests on CRuby over zr's kernel, with
no build. The test file starts ruby again with large stacks and
`--yjit`. Its baseline is `test/baselines/host.txt`:

```console
$ ZR_TEST_HOST=1 bin/minitest test/programs_test.rb
```

## Collect at every allocation

Add `ZR_GC_STRESS=1` after a change to the heap, the frames or the roots:

```console
$ ZR_GC_STRESS=1 ZR_PROGRAMS=lang/blocks bin/minitest test/programs_test.rb
$ ZR_GC_STRESS=1 rake test:programs
```

A value that the collector does not find then fails at once.

## Accept a new snapshot

Some tests compare output with a file in the repository: the HIR dumps,
the disassembly listing, the descriptions and the libSystem list. If
your change must change one of these files, write it again with
`ZR_BLESS=1`, then read the diff:

```console
$ ZR_BLESS=1 bin/minitest test/unit/description_test.rb
$ git diff lib/zr/runtime/ext/os/
```

A change to the signature of a kernel def, or to a struct or a constant
under `lib/zr/runtime/kernel/`, always changes the description.

## Check that an expected output is still ruby's

`zr-dev expect --check` runs each program under ruby 4.0.7 and
compares the output with the files beside the program. It compiles
nothing and writes nothing:

```console
$ ruby tool/zr-dev.rb expect --check test/programs/core/string
$ ruby tool/zr-dev.rb expect --check
```

Without `--check`, `zr-dev expect` writes the files again. See
[How to add a program test](add-a-program-test.md).

## Run the tests for another target

```console
$ ZR_TARGET=wasm32-wasi ZR_PROGRAMS=cli bin/minitest test/programs_test.rb
```

See [How to test on another target](test-on-another-target.md).

## Check the bootstrap

Run these after a change to the compiler or to the kernel's layouts:

```console
$ ruby tool/zr-dev.rb stage 1
$ ruby tool/zr-dev.rb stage 2
```

`zr-dev stage 2` takes about ten minutes and 5 GB of memory, so run it
alone. See [Bootstrapping](../explanation/bootstrapping.md).

## See the progress of a long run

A test run writes its progress to `tmp/test-progress.txt`. From
another terminal:

```console
$ ruby tool/zr-dev.rb progress
```

## Find the slow tests

```console
$ SLOW=1 bin/minitest test/unit
$ SLOW=1 rake test:unit
```

Both also report the 25 slowest files and the 20 slowest tests.

## Check the code style

```console
$ rake lint
```
