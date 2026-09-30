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
The first build takes a few minutes. `bin/test` builds the runtime
again when a change under `lib/` or `runtime/` makes it out of date.
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
$ bin/test
```

This runs the two tiers, one after the other: `test/unit`, then
`test/programs`. `rake test` does the same. `rake` runs `rake lint`
first, then the tests. At the end, `bin/test` prints the time of each
step, for example
`bin/test: 41.20 s (load 1.10 s, prebuild 0.40 s, require 0.90 s, tests 38.80 s)`.

## Run one tier, one directory or one file

Give `bin/test` one or more paths:

```console
$ bin/test test/unit
$ bin/test test/programs
$ bin/test test/programs/core/string
$ bin/test test/programs/core/string/blocks/lambda_arrow_string_return.rb
$ bin/test test/unit/wasm_test.rb test/unit/exe_test.rb
$ bin/test wasm_test.rb
```

A bare file name is found below `test/`. A path below
`test/programs` runs the program tests there: a directory runs each
program below it that has a `.rb.expected` file. `rake test:unit` and
`rake test:programs` run one tier.

## Run some unit tests

Put minitest options after the paths, or set `N` or `X`. A rake
task also takes them as arguments:

```console
$ bin/test test/unit -n /deduplicated/
$ N='/Hygiene|Exe|Target/' bin/test test/unit
$ X=/encoding/ bin/test test/unit/cli_test.rb
$ rake test:unit N=/frozen/
```

The options apply only to the unit tier. To select program tests, give
their paths.

To run the test at one line, use minitest's own command:

```console
$ bundle exec minitest test/unit/cli_test.rb:214
```

`minitest` loads the file before the tier's helper. A file that needs
the tier's load order runs only under `bin/test`.

When a unit run fails, it prints a command that runs each failure
again alone. When a program test fails, the runner prints `FAIL:` or
`ERROR:` and the path of the program below `test/programs`; give that
path to `bin/test` to run it again. See
[Program tests](../reference/program-tests.md#results).

## Run another project's program tests

```console
$ bin/test --corpus ~/dev/spinel/test
```

`--corpus DIR` runs the program tests below `DIR` (spinel's files
have the same names). Its baseline is
`test/baselines/corpus/<project>-<triple>.txt`. See
[Program tests](../reference/program-tests.md#another-projects-tests).

## Run the tests that a change can reach

```console
$ bin/test --changed
$ bin/test --changed --base origin/main
$ ruby tool/zr-dev.rb affected --dry-run
```

`bin/test --changed` reads the diff against `main`, or against
`--base`, and runs the tests that the changed files can reach. A
changed unit test file runs itself, and a changed program, or a file
beside it, runs the program. For a file under `runtime/core`, these
are the directory of its class and every program test that uses the
class name. For a file under `lib/zr` that does not change what a
build writes, these are the unit tests that load it, and
`test/programs/cli` when `exe/zr` loads it. A change to the compiler, the kernel or the test support reaches
every test: then `bin/test --changed` runs nothing and tells you so,
because a full run is a decision for you. `zr-dev affected` does the
same, and `--dry-run` prints the paths and runs nothing.

## Use fewer workers

`bin/test` runs one worker process for each 2 GB of memory. It keeps a
quarter of the memory (at least 4 GB) and two cores free, and prints
the number when it starts. A 16 GB, 12-core Mac gets 6 workers. If the
machine is slow or swaps during a run, set fewer:

```console
$ MT_CPU=4 bin/test test/programs/core/string
```

Do not run two tiers or two `bin/test` commands at the same time. Each
one takes its workers from the same memory.

## Collect at every allocation

Add `GC=stress` after a change to the heap, the frames or the roots:

```console
$ GC=stress bin/test test/programs/lang/blocks
$ rake test:programs GC=stress
```

A value that the collector does not find then fails at once.

## Accept a new snapshot

Some tests compare output with a file in the repository: the HIR dumps,
the disassembly listing, the descriptions and the libSystem list. If
your change must change one of these files, write it again with
`ZR_BLESS=1`, then read the diff:

```console
$ ZR_BLESS=1 bin/test test/unit/description_test.rb
$ git diff runtime/ext/os/
```

A change to the signature of a kernel def, or to a struct or a constant
under `runtime/kernel/`, always changes the description.

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
$ TARGET=wasm32-wasi bin/test test/programs/cli
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

The unit tier writes its progress to `tmp/test-progress.txt`. From
another terminal:

```console
$ ruby tool/zr-dev.rb progress
```

## Find the slow tests

```console
$ SLOW=1 bin/test test/unit
$ SLOW=1 rake test:unit
```

Both also report the 25 slowest files and the 20 slowest tests.
`SLOW` applies only to the unit tier.

## Check the code style

```console
$ rake lint
```
