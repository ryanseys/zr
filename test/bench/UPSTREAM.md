# Benchmark provenance

Copied from the `benchmark/` suite of [spinel](https://github.com/matz/spinel)
(MIT License, Copyright (c) 2024- Yukihiro Matsumoto), zeo's C-emitting
predecessor, whose golden-output benchmark discipline this suite continues.
Many programs are in turn adaptations of classic Ruby benchmark corpora
(the Computer Language Benchmarks Game shapes, yjit-bench-style micro
benchmarks).

Local workload divergence: `bm_tree_walker.rb`'s round count was reduced
400 -> 100 (2026-08-25) so a 10-sample criterion bank stays affordable
while zeo's dispatch-bound gap on it is still open; the polymorphic
structure is unchanged.

Each `bm_<name>.rb` prints deterministic output, and carries ruby 4.0.6's
recording of it under `__END__` in the format of `docs/test-format.md`,
like every other corpus program. `ze0 bench` builds each one, checks the
answer against that recording before it keeps any time (a wrong answer
fails the row -- the speed of a wrong answer means nothing), and reports
the median of three runs against `ruby` and `ruby --yjit`. The medians
go to `results.tsv`, which is a text diff away from the last run.
