# How to measure performance

This guide shows you how to measure how fast zr's binaries run, and
how fast zr builds them. The options of each task are in
[Rake tasks and scripts](../reference/rake-tasks.md#performance).

## Time the binaries

`rake bench` builds each program in `benchmark/`, checks its output
against the recording, and then times it beside `ruby` and
`ruby --yjit`:

```console
$ rake 'bench[fib tak nbody]'
$ rake 'bench[--runs 5 fib]'
```

A program with a wrong output fails, and has no time. The report gives
the median of the runs: `zr` is the binary's wall-clock time, and `cpu`
is the user and system time of the binary itself, which other work on
the machine does not change. The task measures each run with
`Benchmark.measure` from the [benchmark](https://github.com/ruby/benchmark)
gem, and forks nothing beside a timed run.

A run of all the benchmarks writes its report to
`benchmark/results/<stamp>-<revision>.txt`, named by the time and the
commit. Commit the report, so that a later run can compare with it by
revision. A run of some benchmarks writes `tmp/bench/latest.txt`.

`rake bench:check` compares the newest report with the one before it,
or the two reports that you give, as paths or as revisions. A program
of 100 ms or more whose wall-clock time changed by a tenth fails the
check. A shorter program is only listed.

```console
$ rake bench:check
$ rake 'bench:check[caebda07 be347192]'
$ rake 'bench:check[benchmark/results/20260922-0426-caebda07.txt tmp/bench/latest.txt]'
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

`rake compile` is `rake bench` for the compiler. It builds each rung of
`benchmark/compile/` and reports the seconds of each phase. Thus a
change to the total shows which phase changed.

```console
$ rake compile
$ rake 'compile[--runs 5 bundler]'
$ rake 'compile[--write]'          # writes the table to tmp/bench/compile.txt
```

The rungs are a series of require graphs: `hello` requires nothing,
`stdlib` requires six libraries, and `rubygems` and `bundler` require
the two largest. The runtime is already built, and the task discards
the first run of each rung.

## Measure the size of the generated code

`rake codesize` counts the instructions that the backend writes for
the whole runtime. Save a run before your change, and compare after
it:

```console
$ rake 'codesize[--all]' > tmp/codesize-before.tsv
$ rake 'codesize[tmp/codesize-before.tsv]'
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
