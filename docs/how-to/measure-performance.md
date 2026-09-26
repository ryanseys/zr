# How to measure performance

This guide shows you how to measure how fast zr's binaries run, and
how fast zr builds them. The options of each command are in
[Tools](../reference/tools.md#measure). This guide writes `zr-dev`
for `ruby tool/zr-dev.rb`.

## Time the binaries

`zr-dev bench` builds each program in `benchmark/`, checks its output
against the recording, and then times it beside `ruby` and
`ruby --yjit`:

```console
$ ruby tool/zr-dev.rb bench fib tak nbody
$ ruby tool/zr-dev.rb bench --runs 5 fib
```

A program with a wrong output fails, and has no time. The summary on
the terminal gives the median of the runs: `zr` is the binary's
wall-clock time, `cpu` is the user and system time of the binary
itself, which other work on the machine does not change, and `ruby` and
`yjit` are ruby's wall-clock times. The report file gives each program
in the layout of the benchmark gem: a row each for `zr`, `ruby` and
`yjit`, with the columns `user`, `system`, `total` and `real`. The command measures each run with
`Benchmark.measure` from the [benchmark](https://github.com/ruby/benchmark)
gem, and forks nothing beside a timed run.

A run of all the benchmarks writes its report to
`benchmark/results/<stamp>-<revision>.txt`, named by the time and the
commit. Commit the report, so that a later run can compare with it by
revision. A run of some benchmarks writes `tmp/bench/latest.txt`.

`zr-dev bench --check` compares the newest report with the one before
it, or the two reports that you give, as paths or as revisions. A program
of 100 ms or more whose wall-clock time changed by a tenth fails the
check. A shorter program is only listed.

```console
$ ruby tool/zr-dev.rb bench --check
$ ruby tool/zr-dev.rb bench --check caebda07 be347192
$ ruby tool/zr-dev.rb bench --check benchmark/results/20260922-0426-caebda07.txt tmp/bench/latest.txt
```

A time is valid only on the machine that measured it. Compare two
reports from the same machine, and run benchmarks on a quiet machine,
not at the same time as a test run.

## Time a build

Set `ZR_TIMING=1` to print how long each phase of a build takes:

```console
$ ZR_TIMING=1 exe/zr build app.rb -o app
```

The first build after a change under `runtime/` or `lib/` compiles the
runtime again. Build two times, and time the second build, unless you
want to measure the cold build.

## Time the compiles

`zr-dev compile` is `zr-dev bench` for the compiler. It builds each
rung of `benchmark/compile/` and reports the seconds of each phase. Thus a
change to the total shows which phase changed.

```console
$ ruby tool/zr-dev.rb compile
$ ruby tool/zr-dev.rb compile --runs 5 bundler
$ ruby tool/zr-dev.rb compile --write   # writes the table to tmp/bench/compile.txt
```

The rungs are a series of require graphs: `hello` requires nothing,
`stdlib` requires six libraries, and `rubygems` and `bundler` require
the two largest. The runtime is already built, and the command discards
the first run of each rung.

To guard the compiled compiler against a slowdown, keep a baseline.
`--commit` writes one to `benchmark/results/compile/`, and `--check`
fails if the compiler is slower than the newest baseline. Both need
`--zr`:

```console
$ ruby tool/zr-dev.rb compile --zr --commit
$ ruby tool/zr-dev.rb compile --zr --check
```

## Measure the size of the generated code

`zr-dev codesize` counts the instructions that the backend writes for
the whole runtime. Save a run before your change, and compare after
it:

```console
$ ruby tool/zr-dev.rb codesize --all > tmp/codesize-before.tsv
$ ruby tool/zr-dev.rb codesize --against tmp/codesize-before.tsv
```

## Profile the compiler

The compiler is Ruby, so a Ruby profiler works on it. The Gemfile has
[vernier](https://github.com/jhawthorn/vernier) in its development
group:

```console
$ ZR_TUNE=0 bundle exec vernier run -- ruby exe/zr build app.rb -o app
```

`ZR_TUNE=0` prevents `zr` from starting itself again with its
collector settings, so the profile is of the process that vernier
started.
