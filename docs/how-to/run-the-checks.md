# How to run the checks

This guide shows you how to run ze0's own tests in a checkout: the
checks, the corpus, and the bootstrap. Run the smallest set that covers
your change, and the full set before you merge.

## Run the checks that cover a change

The checks are Minitest files in `test/unit/`. `FILTER` gives part of
each file name:

```console
$ rake test:unit FILTER="hygiene exe target"
```

Each file runs in a process of its own. A file that declares
`# shards: N` runs in N processes.

To run one check file with Minitest's own options, run it directly:

```console
$ rake 'test:one[test/unit/wasm_test.rb,-n test_data_objects_share_a_segment]'
```

## Run every check

```console
$ rake test:unit
```

This takes several minutes. It runs up to four files at a time. To change that
number, set `ZE0_JOBS`. A check that needs wasmtime skips when wasmtime
is not installed.

## Accept a new snapshot

Some checks compare against a file in the repository: the HIR dumps,
the disassembly listing, the eval descriptions and the libSystem list.
When your change is meant to change one of these, write it again with
`ZE0_BLESS=1`, then read the diff:

```console
$ ZE0_BLESS=1 rake test:unit FILTER=description
$ git diff rt/ext/os/
```

A change to a kernel def's signature, a struct or a constant under
`rt/kernel/` always needs the description written again.

## Run the corpus

Run a directory, or any part of a case's name:

```console
$ bin/ze0 test lang/blocks/
$ bin/ze0 test core/string/ core/array/
$ bin/ze0 test ze0::
```

To collect at every allocation, add `--gc stress`. Use it for a change
to the heap, the frames or the roots:

```console
$ bin/ze0 test lang/blocks/ --gc stress
```

To run every program, use `--all`. This takes a long time, so run it
before a release, not for each change.

## Run the corpus for another target

```console
$ bin/ze0 test ze0:: --target wasm32-wasi --baseline test/baselines/wasm32-wasi.txt
```

With `--baseline`, the run passes when each defect is one the baseline
file already lists.

## Check the bootstrap

Run these after a change to the compiler or the kernel's layouts:

```console
$ rake stage1
$ rake stage2
```

`stage1` compiles the compiler twice and wants the same bytes both
times. `stage2` builds the compiler with itself and wants the same
binary that ruby built. `stage2` takes about ten minutes and 5 GB of
memory, so run it alone. To learn why these matter, read
[Bootstrapping](../explanation/bootstrapping.md).

## Every task

`rake -T` names them all. The ones a change usually wants:

```console
$ bundle exec rake                       # every test
$ bundle exec rake test:unit             # ze0's internals, seconds
$ bundle exec rake test:spec             # Ruby held to ruby
$ bundle exec rake test:spec FILTER=string
$ bundle exec rake test:spec GC=stress
$ bundle exec rake stage1 stage2
```
