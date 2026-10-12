# Benchmark recordings

Two formats keep ruby's output beside a program:

- A program test in `test/programs/` has `foo.rb.expected` and the
  other files of [Program tests](program-tests.md). `zr-dev expect`
  writes them.
- A benchmark in `benchmark/` has a recording, which this page
  describes. `zr-dev record` writes it, and `zr-dev bench` reads it
  (`Harness::Answer.beside`).

A benchmark is a `.rb` file and nothing else: no header and no
trailer. `ruby benchmark/bm_so_lists.rb` runs it.

The recording is beside it, in files that contain only ruby's bytes:

```
benchmark/
  bm_so_lists.rb        the program
  bm_so_lists.out       what it wrote to stdout
  bm_so_lists.err       what it wrote to stderr, if it wrote something
  bm_so_lists.status    the exit status, if it was not 0
  bm_so_lists.signal    the number of the signal that stopped it, if one did
```

Nothing is escaped and nothing has a marker. Thus a program can write
any bytes (binary output, invalid UTF-8, a last line with no newline),
and a wrong output is a `diff` of two files.

## Recording

`zr-dev record <path>` (`tool/record.rb`) runs the benchmark under
the pinned ruby, from the repository root, with an empty stdin and only
the reference gems, and writes the files above. That ruby is the only
source of expected outputs, so nothing else writes them, and nobody
writes them by hand. The command does not change a benchmark that has
a recording. `zr-dev record --again <path>` writes the recording again.
A change of output is usually a change of program.

`zr-dev record` takes only a path below `benchmark/`. For a program
test, it tells you to use `zr-dev expect`.
