# How to run the tests

This guide shows you how to run zr's tests in a checkout. Run the
smallest set of tests that covers your change. Run all the tests before
you open a pull request.

For the full list of rake tasks, `zr-dev` commands and test variables,
see [Tools](../reference/tools.md). This guide writes `zr-dev` for
`bin/zr-dev`. To learn how a
tier runs, see [How the tests run](../explanation/how-the-tests-run.md).

## Before you start

You need the ruby that `.ruby-version` names (for example
`mise install ruby@$(cat .ruby-version)` or
`rbenv install $(cat .ruby-version)`). The full test suite runs on an
Apple Silicon Mac with 16 GB of memory or more. On Linux, you can work
on the Linux targets and on `wasm32-wasi` (see
[Run the tests for another target](#run-the-tests-for-another-target)).
[wasmtime](https://wasmtime.dev) is optional; without it, the tests
that run WebAssembly modules skip.

Set up the checkout one time:

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup
```

`bin/setup` installs the gems and builds the runtime for this host.
The first build takes a few minutes. A test run builds the runtime
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
$ bin/zr-dev test
```

This runs every `test/**/*_test.rb` file with `bin/minitest`: the unit
tests, the program tests and the C extension tests. `bin/minitest` with
no path does the same, and so does `rake test`. `rake` runs `rake lint` first, then the tests. To time a run, use
the shell's `time`:

```console
$ time bin/zr-dev test --suite unit
```

A run does not have the tests that take minutes for code that the
other tests cover in part, such as `test/unit/core_cache_test.rb`, which
builds the runtime three times. Run them by hand after a change to that
code:

```console
$ ZR_TEST_ALL=1 bin/zr-dev test test/unit/core_cache_test.rb
```

## Run some tests

Give `zr-dev test` one or more paths. A path is a test file, a
directory of test files, a program below `test/programs` or a directory
of them, or a Ruby program of your own anywhere:

```console
$ bin/zr-dev test test/unit/wasm_test.rb test/unit/exe_test.rb
$ bin/zr-dev test test/programs/core/string test/programs/lang
$ bin/zr-dev test test/programs/core/string/blocks/lambda_arrow_string_return.rb
$ bin/zr-dev test --suite unit,ext
```

To run the test at one line of a test file, give the line after the
path:

```console
$ bin/zr-dev test test/unit/cli_test.rb:17
```

`--name` (`-n`) selects tests by name, and `--exclude` (`-e`) leaves
tests out by name. The name of a program test is
`test_<path below test/programs>`:

```console
$ bin/zr-dev test --suite unit -n /deduplicated/
$ bin/zr-dev test test/unit/cli_test.rb -e /encoding/
$ bin/zr-dev test --suite programs -n /stdlib.uri/
```

`--list` prints the `bin/minitest` command and the tests that it runs,
and runs nothing.

Without zr-dev, give `bin/minitest` the test files, and set
`ZR_PROGRAMS` to the programs, separated by commas:

```console
$ ZR_PROGRAMS=core/gc,lang bin/minitest test/programs_test.rb
```

## Test a program of your own

A program anywhere is a program test. With no `.rb.expected` file beside
it, the test asks the pinned ruby for the expected output when it runs,
and compares zr's output with that:

```console
$ bin/zr-dev test scratch/try.rb
```

Three options say where the expected output comes from:

| Option | The expected output |
|---|---|
| `--record` | The pinned ruby's, written beside each program first, as `zr-dev expect` writes it. |
| `--verify` | The files beside each program. A program with none fails. |
| `--live` | The pinned ruby's, now. The test reads and writes no file. |

`ZR_EXPECTED=record`, `verify` or `live` does the same without zr-dev. A
directory gives only the programs that have a `.rb.expected` file,
unless one of these options is set.

## Run the failed tests again

When a run fails, minitest prints each failure. A failed program test
shows the diff against ruby's output. When zr does not build or run
the program, the test is an error. A skip tells you why: a baseline
entry or a need that the host does not meet. See
[Program tests](../reference/program-tests.md#results).

Each run records the tests that failed in `tmp/zr-dev-test/failed.txt`,
and takes off each test that passed. To run them again:

```console
$ bin/zr-dev test --failed
```

## Run the tests that a change can reach

```console
$ bin/zr-dev test --changed
$ bin/zr-dev test --changed origin/main
```

`--changed` reads the diff against `main`, or against the revision that
you give, and runs the tests that the changed files can reach. A
changed unit test file runs itself, and a changed program, or a file
beside it, runs the program. For a file under `lib/zr/runtime/core`, these
are the directory of its class and every program test that uses the
class name. For a file under `lib/zr` that does not change what a
build writes, these are the unit tests that load it, and
`test/programs/cli` when `exe/zr` loads it. A change to the compiler,
the kernel or the test support reaches every test: then `--changed`
runs nothing and tells you so, because a full run is a decision for
you (`tool/lib/zr/dev/reach.rb`).

## Use fewer workers

`bin/minitest` runs one worker process for each 2 GB of memory. It keeps a
quarter of the memory (at least 4 GB) and two cores free, and prints
the number when it starts. A 16 GB, 12-core Mac gets 6 workers. If the
machine is slow or swaps during a run, set fewer with `--jobs` (`-j`,
or `MT_CPU`):

```console
$ bin/zr-dev test -j 4 test/programs/core/string
```

Do not run two tiers or two test runs at the same time. Each one takes
its workers from the same memory.

## Stop at the first failure, or change the time limits

`--fail-fast` (`ZR_TEST_FAIL_FAST=1`) runs no more tests after one
fails. `--timeout SECS` sets the time limit of each test and of each
program's build and run. Without zr-dev, `ZR_TEST_SECONDS=N` sets the
limit of each program run and build (default 60 s), and
`ZR_TEST_TIMEOUT=N` the limit of each test in a worker (default 180;
`0` removes it):

```console
$ bin/zr-dev test --fail-fast --suite unit
$ ZR_TEST_SECONDS=300 ZR_TEST_TIMEOUT=0 bin/zr-dev test test/programs/stdlib
```

## Skip the program tests that passed

A program test that passed with the same inputs passes again at once,
from a cache (`test/support/result_cache.rb`). The inputs are the
program and the files beside it, its baseline line, the ruby, the `ZR_*`
variables, and the checkout without the paths that no program reads:
the docs, the unit and ext tests, the benchmarks and the Markdown files
at the top. So after a change to a doc or a unit test, a run builds no
program again, and after a change below `lib/` it runs each one again.
`--no-cache` (`ZR_TEST_FRESH=1`) runs each one:

```console
$ bin/zr-dev test --no-cache test/programs/lang/control
```

## Run the program tests on the host

`--no-build` (`ZR_TEST_HOST=1`) runs the program tests on CRuby over
zr's kernel, with no build. The test file starts ruby again with large
stacks and `--yjit`. Its baseline is `test/baselines/host.txt`:

```console
$ bin/zr-dev test --no-build --suite programs
$ bin/zr-dev test --no-build --no-cache test/programs/lang/control
```

## Collect at every allocation

Add `--gc-stress` (`ZR_GC_STRESS=1`) after a change to the heap, the
frames or the roots:

```console
$ bin/zr-dev test --gc-stress test/programs/lang/blocks
$ ZR_GC_STRESS=1 rake test:programs
```

A value that the collector does not find then fails at once.

## Hand the GVL on at every safe point

After a change to the threads, the scheduler or the kernel's shared
state, run the thread areas with `--gvl-stress` (`ZR_GVL_STRESS=1`),
which hands the GVL to the next thread at every safe point, and with
`--gvl-check` (`ZR_GVL_CHECK=1`), which stops the program when C API
code runs on an OS thread that does not hold the GVL.
`--green-threads` (`ZR_THREADS=green`) runs every thread on one OS
thread, as on wasm32-wasi:

```console
$ bin/zr-dev test --gvl-stress --gvl-check test/programs/core/thread
$ bin/zr-dev test --green-threads test/programs/core/thread
```

A state that two threads share without a rule in `lib/zr/lock_plan.rb`
then shows at once.

## Accept a new snapshot

Some tests compare output with a file in the repository: the HIR dumps,
the disassembly listing, the libSystem list and the files that some
generators write (prism's Ruby, its encoding tables and the builtin
lines). If your change must change one of these
files, write it again with `ZR_BLESS=1`, then read the diff:

```console
$ ZR_BLESS=1 bin/zr-dev test test/unit/hir_test.rb
$ git diff test/hir/
```

## Check that an expected output is still ruby's

`zr-dev expect --check` runs each program under the pinned ruby and
compares the output with the files beside the program. It compiles
nothing and writes nothing:

```console
$ bin/zr-dev expect --check test/programs/core/string
$ bin/zr-dev expect --check
```

Without `--check`, `zr-dev expect` writes the files again. See
[How to add a program test](add-a-program-test.md).

## Run the tests for another target

The pinned ruby on macOS gives every expected output. A target is
correct when it gives the same output. Set the target with `--target`
(`ZR_TARGET`):

```console
$ bin/zr-dev test --target wasm32-wasi test/programs/cli
$ bin/zr-dev test --target aarch64-linux-musl test/programs/lang/methods
```

The tests build each program for that target and start it as that
target starts: a binary on its own host, a WASI module under wasmtime.
For `wasm32-wasi`, build the WASI runtime first (`rake build:wasm`). For
the targets and what each one supports, see
[Targets](../reference/targets.md).

To run a target's binaries on another machine, give a command in
`ZR_TEST_EXEC`. The binary and its arguments follow its words, and the
command runs them on a host of the target, in the test's directory,
with the test's environment. The other host must see this checkout and
`TMPDIR` at the same paths:

```console
$ ZR_TEST_EXEC=~/bin/on-x86_64 TMPDIR=$PWD/tmp/run bin/zr-dev test --target x86_64-linux-musl test/programs/cli
```

### The baselines

A target's baseline file, `test/baselines/<triple>.txt`, lists the
program tests that the target can fail, and the reason for each. One
line has a key (the path below `test/programs`), a tab, and the reason.
A line that starts with `#` is a comment:

```
# wasi has no processes and no signals.
cli/core/process/process_spawn.rb	spawn() is unimplemented on wasi
```

A test in the baseline that fails is skipped, with the reason. A test
in the baseline that **passes** makes the run fail, with the message
`this now passes: take it off test/baselines/<triple>.txt`. Add a line
only when the target cannot do what the test needs; a line is not a
place for a bug.

### Output that is correct only on one platform

A program test can keep the stdout and the stderr of a recording in
their own files: `foo.rb.wasi.expected`, or on Linux the libc's,
`foo.rb.linux-gnu.expected` and `foo.rb.linux-musl.err.expected`. A
test there compares with that file, and elsewhere with
`foo.rb.expected`. On Linux, `zr-dev expect` writes the files of the
libc of its ruby when the output is not macOS's. A test that a platform
cannot run gives the platforms that can run it in `foo.rb.needs`
(`macos`, `linux`, `linux-gnu`, `linux-musl`, `wasi`). See
[Program tests](../reference/program-tests.md).

To record both libcs, run the pinned ruby's images, with the checkout
at its own path (not at /zr: a runtime names zr's own files there):

```console
$ docker run --rm -v "$PWD:$PWD" -w "$PWD" "ruby:$(cat .ruby-version)" \
    sh -c 'bundle install && bin/zr-dev expect --all test/programs/core/io'
$ docker run --rm -v "$PWD:$PWD" -w "$PWD" "ruby:$(cat .ruby-version)-alpine" \
    sh -c 'apk add --no-cache build-base git tzdata && bundle install && bin/zr-dev expect --all test/programs/core/io'
```

### The Linux tests in the container that CI uses

```console
$ docker run -d --name alpine -v "$PWD:$PWD" -w "$PWD" "ruby:$(cat .ruby-version)-alpine" sleep infinity
$ docker exec alpine apk add --no-cache build-base git tzdata
$ docker exec alpine git config --global --add safe.directory "$PWD"
$ docker exec alpine bundle config set --global without development
$ docker exec alpine bundle install
$ docker exec alpine bundle exec rake build
$ docker exec alpine bin/zr-dev test --target aarch64-linux-musl test/programs/cli
```

### Run what one CI lane runs

CI has one lane for each target (`.github/workflows/lane.yml`). Each lane
runs the unit files of its target, then the programs of a push. On the
nightly run, it runs every program, in shards. To run the same tests
here, on a host of that target:

```console
$ ruby .github/scripts/lanes.rb units aarch64-apple-darwin      # the lane's unit files
$ ruby .github/scripts/lanes.rb units aarch64-apple-darwin --run
$ ZR_PROGRAMS=cli bin/minitest test/programs_test.rb
$ ZR_PROGRAMS=lang/methods,core/string bin/minitest test/programs_test.rb
$ bin/zr-dev test --suite programs --shard 2/6                   # a nightly shard
$ ruby .github/scripts/lanes.rb untagged --run                   # the files of no lane
```

`ruby .github/scripts/lanes.rb matrix` prints each lane's runner, its
shards and its settings. A unit file goes to a lane through its
`# zr-test: on KIND` comment ([how the tests run](../explanation/how-the-tests-run.md)).

## The reference ruby and its gems

Every expected output comes from the ruby that `.ruby-version` names
(`test/support/harness/reference.rb`). That ruby runs with the gems of
its own install, and without this checkout's bundle, `RUBYOPT` or
`RUBYLIB`. A stock install is enough for most tests. When `vendor/`
carries another version of a gem than the install has (a port at zr's
version, see `lib/zr/library/ports.rb`), install that version into the
pinned ruby, so both sides load the same code:

```console
$ gem install json -v 3.0.2
```

To keep the reference apart from your other gems, fill a directory and
name it in `ZR_REFERENCE_GEM_HOME`. The reference ruby then uses it as
its `GEM_HOME` and `GEM_PATH`:

```console
$ gem install --install-dir ~/zr-reference --no-document json:3.0.2 rbs:4.2.0
$ export ZR_REFERENCE_GEM_HOME=~/zr-reference
```

Record and check with the same set of gems.

## Check the bootstrap

Run these after a change to the compiler or to the kernel's layouts:

```console
$ bin/zr-dev stage 1
$ bin/zr-dev stage 2
```

`zr-dev stage 2` takes about ten minutes and 5 GB of memory, so run it
alone. See [Bootstrapping](../explanation/bootstrapping.md).

## See the progress of a long run

A test run writes its progress to `log/minitest/latest.progress.log`,
and each failure's full report to `log/minitest/latest.failures.log`
as it happens. From another terminal:

```console
$ cat log/minitest/latest.progress.log
$ cat log/minitest/latest.failures.log
```

`log/minitest/latest.log` holds all of the run's output. A run that
you stop with ^C keeps these files, and prints the report of the tests
that ran.

## Find the slow tests

A run of 20 tests or more prints its 10 slowest tests at the end, and
the 10 groups that took the most time in all: test files, and
directories of program tests. Each run also keeps the time of each
test in `tmp/zr-dev-test/times.tsv`, as each test ends, so a run that
stops early keeps its times too. To see the slowest tests of the runs
so far, with no run:

```console
$ bin/zr-dev test --slowest
$ bin/zr-dev test --slowest 50
```

`SLOW=<n>` prints `n` tests and groups for a run of any size, and `SLOW=1`
prints 20, with the time that the program tests spent to lower, link
and run, by directory. `SLOW=0` prints nothing:

```console
$ SLOW=1 bin/zr-dev test --suite unit
```

## Check the code style and the types

```console
$ rake lint
$ bin/steep check
```

`rake lint` runs RuboCop: the Lint cops and the cops that `.rubocop.yml`
adds, each with its reason. `bin/steep check` runs Steep on the compiler
and on the kernel. Annotate methods with inline RBS
(`#: (Integer) -> String`). A declaration that inline RBS cannot type
has `# @rbs skip` above it and its types in `sig/zr/`.

`COVERAGE=1 bin/minitest <paths>` measures the line and branch coverage
of `lib/` and writes `tmp/coverage/index.html`. It gates nothing.

## Write a changelog line

When a user sees a change (a feature, a changed behavior or a fix), add
a line to `CHANGELOG.md` under `[Unreleased]`. A change to the tests,
the tools or the docs gets no line.
