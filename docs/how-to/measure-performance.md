# How to measure performance

This guide shows you how to measure how fast ze0's binaries run and how
fast ze0 builds them.

## Time the binaries

`rake bench` builds each program in `benchmark/`, checks its answer
against the recording, and then times it beside `ruby` and `ruby
--yjit`:

```console
$ rake 'bench[fib tak nbody]'
$ rake 'bench[--runs 5 fib]'
```

A row with a wrong answer fails, and has no time. The report gives the
median of the runs: `ze0` is the binary's wall clock, and `cpu` beside it
is the user and system time the binary itself spent, which the machine's
other work does not move. Each run is clocked with `Benchmark.measure`
from the [benchmark](https://github.com/ruby/benchmark) gem, a
development dependency, and nothing forks beside a timed run.

The report is also written, in that gem's own layout, to
`tmp/bench/latest.txt`, and the run before it is kept as
`tmp/bench/previous.txt`. `rake bench:check` reads the two: a program of
100 ms or more whose wall clock moved by a tenth fails the check, and a
shorter one is only named. Give it two reports to compare any pair:

```console
$ rake bench:check
$ rake 'bench:check[tmp/bench/before.txt tmp/bench/latest.txt]'
```

Nothing under `tmp/` is committed: a time is the machine's and the
day's. Run benchmarks on a quiet machine, and not beside a test run.

## Time a build

Set `ZE0_TIMING=1` to print how long each phase of a build takes:

```console
$ ZE0_TIMING=1 exe/ze0 build app.rb -o app
```

The first build after a change under `rt/` or `lib/` compiles the
runtime again. Build twice, and time the second build, unless you want
to measure the cold build.

## Time the compiles

`rake compile` is `rake bench` for the compiler: it builds each rung of
`benchmark/compile/` and reports the seconds each phase took, so a
change that moves the total says which phase it moved.

```console
$ rake compile
$ rake 'compile[--runs 5 bundler]'
$ rake 'compile[--write]'          # writes the table to tmp/bench/compile.txt
```

The rungs are a ladder of require graphs: `hello` requires nothing,
`stdlib` requires six of the libraries ze0 carries, and `rubygems` and
`bundler` enter at the two largest umbrellas there are. The runtime is
warm, as it is for everyone who is not building ze0 for the first time,
and the first run of each rung is thrown away.

## Measure the size of the generated code

`rake codesize` counts the instructions the backend writes for the
whole runtime. Save a run before your change and compare after it:

```console
$ rake 'codesize[--all]' > tmp/codesize-before.tsv
$ rake 'codesize[tmp/codesize-before.tsv]'
```

## Profile the compiler

The compiler is Ruby, so a Ruby profiler works on it. The Gemfile has
[vernier](https://github.com/jhawthorn/vernier) in its development
group:

```console
$ ZE0_GC=0 bundle exec vernier run -- ruby exe/ze0 build app.rb -o app
```

`ZE0_GC=0` stops `ze0` from starting itself again with its
collector settings, so the profile is of the process vernier started.
