# How the tests run

This page explains how zr's tests are organized and how a test run
uses processes, memory and the cache. For the steps, see
[How to run the tests](../how-to/run-the-tests.md).

## Three tiers

The tests are in three tiers. Each tier is a directory below `test/`.

| Tier | Directory | Tests |
|---|---|---|
| unit | `test/unit/` | zr's own internals: the parser port, the passes, the backends, the linkers, the harness, the tools. Minitest, in plain `def test_...` methods |
| programs | `test/programs/`, run by `test/programs_test.rb` | Ruby behavior and the product. Each test is a plain Ruby program that zr builds and runs, checked against the pinned ruby's output |
| ext | `test/ext/` | C extensions that zr links into a binary through its copy of ruby's C API. Each test builds a small extension from C in the test, and checks its answers against the pinned ruby's |

The ruby that `.ruby-version` names is the reference for the program
tests. Every expected
output comes from ruby (`zr-dev expect`), never from a person. See
[The contract](the-contract.md) and
[Program tests](../reference/program-tests.md).

`bin/minitest` runs all three tiers. Each test file loads minitest and
`test/test_helper.rb`. `test/programs_test.rb` defines one minitest
test for each program, named `test_<path below test/programs>`, and
`test/support/programs.rb` checks each one.

## The runtime is built first

Every program that a test builds links the same runtime. Before a run
starts its workers, a minitest plugin builds the runtime for this host
if it is not built or is out of date (`Zr::Test::Built`). It then loads the
runtime into the parent process, so all the workers share one copy.
After a change under `lib/` or `lib/zr/runtime/`, this build takes a few
minutes.

A unit test file that builds a program says so in its first lines:

```ruby
# zr-test: runtime   # it builds a program, without eval support
# zr-test: eval      # it builds a program that evals
```

A unit file without this comment builds nothing, so a run of such
files does not build or load the runtime, and starts at once
(`test/support/needs.rb`). In a test whose file does not declare
`runtime`, the first use of the runtime raises. It raises also when the
cache is warm, so a test passes or fails in the same way on every
machine.

A run of program tests always needs the runtime. It also builds eval
support when one of its programs evals.

## A run forks its workers

The parent process loads zr and every test file. It then gives the
work to forked workers, several at a time. It gives each test method to
a worker (`Zr::Test::ForkPool`), so no worker waits while another
worker has many tests left. A program test is one test method, so a
worker builds the program in its own process, and loads nothing again.

Forks, not threads, give the parallel work. A zr compile is Ruby code,
and the GVL lets only one thread run Ruby at a time.

Forks also keep the memory use flat. Ruby does not give heap pages
back to the system. Thus a worker that grows past `ZR_TEST_RECYCLE_MB`
stops, and the parent forks a new one. The parent does not grow, so
the whole run stays near `workers × ZR_TEST_RECYCLE_MB` above the
parent.

`MT_CPU` sets the number of workers. Its default keeps memory and two
cores free (`test/support/workers.rb`), because a compile and the
program that it builds need some gigabytes together. A machine
that swaps does not fail: it becomes about ten times slower. The
memory limit prevents this.

A worker that the system stops takes its pipe with it. The parent then
reports the test that the worker ran as an error, and the run
continues.

## Limits on each test

A test has a time limit (`ZR_TEST_TIMEOUT`, or a higher limit that a
unit suite sets). A worker that runs one test for longer
is stopped, and its test fails. Thus a compile that loops costs one
test, not the tier.

A program that a test runs also has limits: a time limit
(`ZR_TEST_SECONDS`), and memory limits for the build and the run
(`ZR_TEST_BUILD_MB`, `ZR_TEST_RUN_MB`). [Environment
variables](../reference/environment-variables.md#for-the-tests) gives their defaults. The harness reads the resident
size of the whole process group while it runs, because macOS does not
enforce `RLIMIT_AS`. When the group passes a limit, the harness stops
the whole group.

## Pass, fail, error or skip

A program test passes only when its stdout, its stderr and its exit
status are ruby's. A different output is a failure. A refusal, a build
that fails, a crash of the backend, a trap or a limit is an error. A
test skips only when this machine cannot run it (`.needs`, or no
wasmtime for a WASI target), or when the baseline of the target allows
its failure.

A refusal is an error because the baseline, not the run, lists what
a target may fail. A test in the baseline that passes fails the run.
Thus a new failure always means that something changed, and the
baseline cannot become out of date.

## Kept binaries

The program tests keep the binary of each program in the cache
(`ZR_TEST_BINARIES`, `test/support/binaries.rb`). The key is every
input of the binary's bytes: the runtime's digest, the linker, the
program and its files, and the variables that change a build. A later
run of an unchanged program uses the kept binary and does not build.
`ZR_TEST_BINARIES_GB` limits the size of the kept binaries. A test
below `test/programs/cli/` builds with `zr build` each time, because
the build is what it tests.

## Progress

A test run writes its progress to `tmp/test-progress.txt` at most
once a second: how many tests are done, which failed, the rate, and the
time left. Read the file to look at a run in the background.
Each failure's full report goes to `tmp/test-failures.txt` as it
happens, so you can read a diff before the run ends. At the end, the
run prints the slowest tests and the groups (test files, and
directories of program tests) that took the most time, and counts the
passes that came from the result cache (`test/support/progress.rb`).

## Passes that a run keeps

A program test that passed is a key in the cache (the store's kind
`result`, `test/support/result_cache.rb`). The key is a digest of
everything that a run of the test reads: the program and the files
beside it, its line of the baseline, the ruby, each `ZR_*` and `RUBY*`
variable that can change a result, and the files of zr, of the pinned
ruby and gems, and of the harness that loads the program tests. A
later run with the same key passes the test at once, with no build, in
a compiled run as in a host run.

So an edit to `lib/`, `vendor/` or the harness runs each program test
again, and an edit to the docs, to a unit test or to a tool does not.
`bin/zr-dev test --no-cache` (`ZR_TEST_FRESH=1`) runs each test again.

## Times and failures

What lasts from one run to the next is in `tmp/zr-dev-test/`
(`test/support/history.rb`):

- `times.tsv` holds the time of each test, the date of its run and its
  group, the slowest first. A run writes each time to a journal of its
  own as the test ends, so a run that is killed keeps the times so far.
  A test keeps its time until its file is gone or it has not run for 30
  days. `bin/zr-dev test --slowest` reads it.
- `failed.txt` names each test that failed and has not passed since. A
  run removes each test that it ran and that passed, and adds each that
  failed. `bin/zr-dev test --failed` runs them.

`ZR_TEST_TMP` moves these files, so a suite that a test starts does not
write over the run that started it.

## Baselines and pending tests

A target can fail some program tests: `test/baselines/<triple>.txt`
lists each one with its reason, and `host.txt` does the same for a run
on CRuby over the kernel (`test/support/baseline.rb`). A listed test
that fails is a skip that gives the reason. A listed test that passes
fails the run, so each list stays current.

A new ruby (`.ruby-version`) can change what a program prints before zr
matches it. `upgrade.txt` lists those program tests for every target,
and also the unit and extension tests, by file and method
(`test/support/pending.rb`). Each fix deletes its line, and the upgrade
is done when the file is gone. With no `upgrade.txt`, the check costs
nothing.
