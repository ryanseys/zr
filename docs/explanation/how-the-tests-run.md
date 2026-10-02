# How the tests run

This page explains how zr's tests are organized and how a test run
uses processes, memory and the cache. For the steps, see
[How to run the tests](../how-to/run-the-tests.md).

## Two tiers

The tests are in two tiers. Each tier is a directory below `test/`.

| Tier | Directory | Tests |
|---|---|---|
| unit | `test/unit/` | zr's own internals: the parser port, the passes, the backends, the linkers, the harness, the tools. Minitest, in plain `def test_...` methods |
| programs | `test/programs/`, run by `test/programs_test.rb` | Ruby behavior and the product. Each test is a plain Ruby program that zr builds and runs, checked against ruby 4.0.7's output |

ruby 4.0.7 is the reference for the program tests. Every expected
output comes from ruby (`zr-dev expect`), never from a person. See
[The contract](the-contract.md) and
[Program tests](../reference/program-tests.md).

`bin/minitest` runs both tiers. Each test file loads minitest and
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
(600 MB of growth) stops, and the parent forks a new one. The parent
does not grow, so the whole run stays near `workers × 600 MB` above
the parent.

`MT_CPU` sets the number of workers. The default is one for each 2 GB
of memory, after a quarter of the memory (at least 4 GB) is kept free,
and at most two fewer than the cores (`test/support/workers.rb`). A
compile and the program it builds need about 2 GB together. A machine
that swaps does not fail: it becomes about ten times slower. The
memory limit prevents this.

A worker that the system stops takes its pipe with it. The parent then
reports the test that the worker ran as an error, and the run
continues.

## Limits on each test

A test has a time limit (`ZR_TEST_TIMEOUT`, 180 seconds, or a higher
limit that a unit suite sets). A worker that runs one test for longer
is stopped, and its test fails. Thus a compile that loops costs one
test, not the tier.

A program that a test runs also has limits: 60 seconds
(`ZR_TEST_SECONDS`), and memory limits for the build and the run
(`ZR_TEST_BUILD_MB`, `ZR_TEST_RUN_MB`). The harness reads the resident
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
time left. `zr-dev progress` prints the file, so you can look at a run
in the background.
