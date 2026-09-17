# How to measure performance

This guide shows you how to measure how fast ze0's binaries run and how
fast ze0 builds them.

## Time the binaries

`rake bench` builds each benchmark in `test/bench/`, checks its
answer against the recording, and then times it beside `ruby` and
`ruby --yjit`:

```console
$ rake 'bench[fib tak nbody]'
$ rake 'bench[--runs 5 fib]'
```

A row with a wrong answer fails, and has no time. The report gives the
median of the runs. The full run writes `test/bench/results.tsv`.

Run benchmarks on a quiet machine, and not beside a test run.

## Time a build

Set `ZE0_TIMING=1` to print how long each phase of a build takes:

```console
$ ZE0_TIMING=1 exe/ze0 build app.rb -o app
```

The first build after a change under `rt/` or `lib/` compiles the
runtime again. Build twice, and time the second build, unless you want
to measure the cold build.

## Measure the size of the generated code

`tools/codesize.rb` counts the instructions the backend writes for the
whole runtime. Save a run before your change and compare after it:

```console
$ ruby -Ilib tools/codesize.rb --all > tmp/codesize-before.tsv
$ ruby -Ilib tools/codesize.rb tmp/codesize-before.tsv
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
