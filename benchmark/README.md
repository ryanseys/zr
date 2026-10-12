# Benchmarks

Whole programs that `zr-dev bench` builds with zr and times beside
`ruby` and `ruby --yjit`. They are not tests: the tiers under `test/`
hold zr to ruby's answers. But each program has the pinned ruby's recording
of its output beside it, and the harness checks the answer before it
keeps a time. A program that gives a wrong answer gets no time.

```console
$ bin/zr-dev bench                  # every program, five runs each
$ bin/zr-dev bench fib nbody        # the programs whose name holds a word
$ bin/zr-dev bench --runs 3 fib
$ bin/zr-dev bench --target wasm32-wasi
$ bin/zr-dev bench --check          # the newest report against the one before
$ bin/zr-dev bench --check caebda07 be347192
$ bin/zr-dev compile                # what a build costs, by phase
```

The harness measures each run with `Benchmark.measure` from the
[benchmark](https://github.com/ruby/benchmark) gem. So a row gives the
binary's own user and system time beside its wall-clock time, in that
gem's layout. A run of all the programs writes its report to
`results/<stamp>-<revision>.txt`. The stamp is the UTC time of the run,
so the files list in order, and the revision is the commit that it
measured (`-dirty` means that the tree had changes that the commit does
not have). Commit the file with the code, so that a later run can
compare with it by revision. A run of some programs writes
`tmp/bench/latest.txt`, because a partial report does not tell about
the other programs. All the rows of a report come from one machine, so
compare two reports from the same machine only.
`zr-dev gen perf` writes `docs/explanation/performance.md` from the
newest report.

| Holds | |
|---|---|
| `bm_<name>.rb` | one program, deterministic output |
| `bm_<name>.out` | what the pinned ruby printed, written by `zr-dev record benchmark/bm_<name>.rb` |
| `bm_startup.rb` | the floor: a program that prints one line, so its time is the process's start alone |
| `compile/` | the rungs `zr-dev compile` builds, a ladder of require graphs from `hello` to `bundler` |
| `results/` | one report a run of the whole bank, `<stamp>-<revision>.txt` |

To add a program, write `benchmark/bm_<name>.rb` with output that does
not depend on the run, record it, and run `zr-dev bench <name>` once
to see its row. Run the bank on a quiet machine, and never beside a
test run: a time measured beside other work is not a time.

`UPSTREAM.md` says where the programs came from.
