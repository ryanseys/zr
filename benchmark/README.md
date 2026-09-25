# Benchmarks

Whole programs that `zr-dev bench` builds with zr and times beside
`ruby` and `ruby --yjit`. They are not tests -- the tiers under `test/`
hold zr to ruby's answers -- but each carries ruby 4.0.7's recording
of its output beside it, and the harness checks that answer before it
keeps any time: the speed of a wrong answer means nothing.

```console
$ ruby tool/zr-dev.rb bench                  # every program, five runs each
$ ruby tool/zr-dev.rb bench fib nbody        # the programs whose name holds a word
$ ruby tool/zr-dev.rb bench --runs 3 fib
$ ruby tool/zr-dev.rb bench --target wasm32-wasi
$ ruby tool/zr-dev.rb bench --check          # the newest report against the one before
$ ruby tool/zr-dev.rb bench --check caebda07 be347192
$ ruby tool/zr-dev.rb compile                # what a build costs, by phase
```

Each run of a program is clocked with `Benchmark.measure` from the
[benchmark](https://github.com/ruby/benchmark) gem, so a row carries the
binary's own user and system time beside its wall clock. The report is
printed in that gem's layout. A run of the whole bank writes it to
`results/<stamp>-<revision>.txt` -- when it was taken, in UTC, so the
files list in order, and the commit it measured -- and that file is
committed beside the code, so any later run can be read against it by
hash (`-dirty` on the name says the tree had changes the hash does not
name). A run of some rows writes `tmp/bench/latest.txt` instead,
since a partial report says nothing about the rest. Every report says
which machine's day it was: the first line carries the time, and the
rows are one machine's, so read two reports from one machine.

| Holds | |
|---|---|
| `bm_<name>.rb` | one program, deterministic output |
| `bm_<name>.out` | what ruby 4.0.7 printed, written by `zr-dev record benchmark/bm_<name>.rb` |
| `bm_startup.rb` | the floor: a program that prints one line, so its time is the process's start alone |
| `compile/` | the rungs `zr-dev compile` builds, a ladder of require graphs from `hello` to `bundler` |
| `results/` | one report a run of the whole bank, `<stamp>-<revision>.txt` |

To add a program, write `benchmark/bm_<name>.rb` with output that does
not depend on the run, record it, and run `zr-dev bench <name>` once
to see its row. Run the bank on a quiet machine, and never beside a
test run: a time measured beside other work is not a time.

`UPSTREAM.md` says where the programs came from.
