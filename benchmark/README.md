# Benchmarks

Whole programs that `rake bench` builds with ze0 and times beside
`ruby` and `ruby --yjit`. They are not tests -- the tiers under `test/`
hold ze0 to ruby's answers -- but each carries ruby 4.0.6's recording
of its output beside it, and the harness checks that answer before it
keeps any time: the speed of a wrong answer means nothing.

```console
$ rake bench                       # every program, five runs each
$ rake 'bench[fib nbody]'          # the programs whose name holds a word
$ rake 'bench[--runs 3 fib]'
$ rake 'bench[--target wasm32-wasi]'
$ rake bench:check                 # the run just made against the one before
$ rake compile                     # what a build costs, by phase
```

Each run of a program is clocked with `Benchmark.measure` from the
[benchmark](https://github.com/ruby/benchmark) gem, so a row carries the
binary's own user and system time beside its wall clock. The report is
printed in that gem's layout and written to `tmp/bench/latest.txt`, with
the run before it kept as `previous.txt`; nothing is committed, since a
time is the machine's and the day's.

| Holds | |
|---|---|
| `bm_<name>.rb` | one program, deterministic output |
| `bm_<name>.out` | what ruby 4.0.6 printed, written by `rake 'record[benchmark/bm_<name>.rb]'` |
| `bm_startup.rb` | the floor: a program that prints one line, so its time is the process's start alone |
| `compile/` | the rungs `rake compile` builds, a ladder of require graphs from `hello` to `bundler` |

To add a program, write `benchmark/bm_<name>.rb` with output that does
not depend on the run, record it, and run `rake 'bench[<name>]'` once
to see its row. Run the bank on a quiet machine, and never beside a
test run: a time measured beside other work is not a time.

`UPSTREAM.md` says where the programs came from.
