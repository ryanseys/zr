# How to run the checks

This guide shows you how to run ze0's own tests in a checkout: the
units, the specs, the end-to-end programs and the bootstrap. Run the
smallest set that covers your change, and the full set before you
merge.

Three tiers, in the order you reach for them:

| Tier | Holds | Costs |
|---|---|---|
| `rake test:unit` | ze0's own internals | minutes |
| `rake test:spec` | Ruby held to ruby, one compile an example | twelve minutes |
| `rake test:e2e` | whole programs through a real link | a minute |

## Run the units that cover a change

The units are Minitest files in `test/unit/`. `FILTER` gives part of
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

## Run the specs that cover a change

The specs are in `test/spec/<suite>/<area>/`, and `FILTER` gives part
of each file name:

```console
$ rake test:spec FILTER="string blocks"
```

One file runs standalone with minitest's own options, which is the
fastest way to reach one example:

```console
$ ruby -Ilib -Itest test/spec/core/string/frozen_test.rb -n "/deduplicated/"
```

To collect at every allocation, add `GC=stress`. Use it for a change to
the heap, the frames or the roots:

```console
$ rake test:spec FILTER=blocks GC=stress
```

`rake test:spec` with no filter runs all of them: about twelve minutes,
four files at a time. Set `ZE0_JOBS` to change that number.

## Run the end-to-end programs

These build whole programs through a real link, in a child of their
own, and hold each binary to ruby's recording:

```console
$ rake test:e2e
$ ruby -Ilib -Itest test/e2e/binaries_test.rb -n /socket/
```

## Run for another target

```console
$ rake test:e2e TARGET=wasm32-wasi
$ rake test:spec TARGET=aarch64-linux-musl FILTER=blocks
```

A target on its way in is held to what it did rather than to the whole
tier: `test/baselines/<triple>.txt` names the programs it is allowed to
fail. A named program that now passes fails the run, so the file cannot
go stale. See [The program format](../reference/test-format.md).

## Check that a literal is still ruby's word

Every literal a spec asserts was lifted from an answer ruby recorded.
`rake oracle` runs each program under the ruby the `.ruby-version`
pins and holds the example to it, compiling nothing:

```console
$ rake 'oracle[test/spec/core/string]'
$ rake oracle
```

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
$ bundle exec rake test:e2e             # whole programs through a real link
$ bundle exec rake oracle               # every literal re-checked against ruby
$ bundle exec rake stage1 stage2
```
