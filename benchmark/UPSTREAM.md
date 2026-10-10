# Benchmark provenance

Copied from the `benchmark/` suite of [spinel](https://github.com/matz/spinel)
(MIT License, Copyright (c) 2024- Yukihiro Matsumoto), zr's C-emitting
predecessor, whose golden-output benchmark discipline this suite continues.
Many programs are in turn adaptations of classic Ruby benchmark corpora
(the Computer Language Benchmarks Game shapes, yjit-bench-style micro
benchmarks).

Local workload divergence: `bm_tree_walker.rb`'s round count was reduced
400 -> 100 (2026-08-25) so a 10-sample criterion bank stays affordable
while zr's dispatch-bound gap on it is still open; the polymorphic
structure is unchanged.

Each `bm_<name>.rb` prints deterministic output, and carries ruby 4.0.7's
recording of it beside it, in the layout of `docs/reference/benchmark-recordings.md`,
like every other corpus program. `zr-dev bench` builds each one, checks the
answer against that recording before it keeps a time (a wrong answer
fails the row, and gets no time), and reports
the median of five runs against `ruby` and `ruby --yjit`; `README.md`
beside this file says how.
