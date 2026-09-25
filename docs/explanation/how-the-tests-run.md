# How the tests run

This page explains how zr's tests are organized and how a test run
uses processes, memory and the cache. For the steps, see
[How to run the tests](../how-to/run-the-tests.md).

## Three tiers

The tests are in three tiers. Each tier is a directory below `test/`.

| Tier | Directory | Tests |
|---|---|---|
| unit | `test/unit/` | zr's own internals: the parser port, the passes, the backends, the linkers, the harness |
| spec | `test/spec/` | Ruby behavior. Each example is a small program that zr compiles and runs, checked against ruby 4.0.6's output |
| e2e | `test/e2e/` | whole programs, built and linked as a user builds them, checked against their recordings |

ruby 4.0.6 is the reference for the spec and e2e tiers. Every expected
output comes from ruby, never from a person. See
[The contract](the-contract.md).

`bin/test` runs each tier in its own process, because each tier loads
its own helper: `test/test_helper.rb` for the unit and e2e tiers, and
`test/spec_helper.rb` for the spec tier.

## The runtime is built first

Every program that a test builds links the same runtime. Before a tier
starts its workers, `bin/test` builds the runtime for this host if it
is not built or is out of date (`Zr::Test::Built.ready!`). It then
loads the runtime into the parent process, so all the workers share
one copy. After a change under `lib/` or `runtime/`, this build takes a
few minutes.

## A tier forks its workers

One process loads every test file of the tier. It then gives each
example to a forked worker, several at a time (`Zr::Test::ForkPool`).
The unit of work is one example, not one file, so no worker waits while
another worker has many examples left.

Forks, not threads, give the parallel work. A zr compile is Ruby code,
and the GVL lets only one thread run Ruby at a time.

Forks also keep the memory use flat. Ruby does not give heap pages
back to the system. Thus a worker that grows past `ZR_TEST_RECYCLE_MB`
(600 MB of growth) stops, and the parent forks a new one. The parent
does not grow, so the whole run stays near `workers × 600 MB` above
the parent.

`MT_CPU` sets the number of workers. The default is one for each core,
or one for each 2 GB of memory if that is fewer. A compile and the
program it builds need about 2 GB together. A machine that swaps does
not fail: it becomes about ten times slower. The memory limit prevents
this.

A worker that the system stops takes its pipe with it. The parent then
reports the example that the worker ran as an error, and the run
continues.

## Limits on each example

An example has a time limit (`ZR_TEST_TIMEOUT`, 180 seconds, or a
higher limit that the suite sets). A worker that is silent for longer
is stopped, and its example fails. Thus a compile that loops costs one
example, not the tier.

A program that a test runs also has limits: 60 seconds
(`ZR_TEST_SECONDS`, four times longer under `GC=stress`), and memory
limits for the build and the run (`ZR_TEST_BUILD_MB`,
`ZR_TEST_RUN_MB`). The harness reads the resident size of the whole
process group while it runs, because macOS does not enforce
`RLIMIT_AS`. When the group passes a limit, the harness stops the
whole group.

## Skip or fail

A spec example that zr refuses skips. The skip message gives the form
that zr does not support. At the end of the run, the refusal census
counts the skips by form. This list shows what zr does not support
yet. An example whose build makes no binary also skips and is counted.

Only a wrong output, a crash or a timeout is a failure. Thus a new
failure always means that something changed.

## Kept binaries

The spec tier keeps the binary of each example in the cache
(`ZR_TEST_BINARIES`). The key is every input of the binary's bytes:
the runtime's digest, the linker, the program and its files, and the
variables that change a build. A later run of an unchanged example
uses the kept binary and does not build. A directory of specs then
runs in about a third of the time. `ZR_TEST_BINARIES_GB` limits the
size of the kept binaries.

## Progress

A tier writes its progress to `tmp/test-progress.txt` at most once a
second: how many examples are done, which failed, the rate, and the
time left. `zr-dev progress` prints the file, so you can look at a
run in the background.
