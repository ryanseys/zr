# How to run the checks

This guide shows you how to run ze0's own tests in a checkout: the
units, the specs, the end-to-end programs and the bootstrap. Run the
smallest set that covers your change, and the full set before you
merge.

Three tiers, in the order you reach for them:

| Tier | Holds | Costs |
|---|---|---|
| `rake test:unit` | ze0's own internals | minutes |
| `rake test:spec` | Ruby held to ruby, one compile an example | minutes |
| `rake test:e2e` | whole programs through a real link | a minute |

Each tier is a `Minitest::TestTask`, so each takes minitest's own
switches rather than a language of ours:

| Say | To |
|---|---|
| `N=/utf8/` | run only the examples whose name matches |
| `X=/slow/` | leave out the examples whose name matches |
| `A="--verbose"` | pass anything else to minitest |
| `MT_CPU=4` | run four workers instead of the default |

A tier also defines three tasks beside it: `rake test:spec:slow` names
the slowest 25 files, `rake test:unit:isolated` says which files
fail when run on their own, and `rake test:spec:cmd` prints the command
without running it.

## How a tier runs

One process loads every file in the tier and then hands each example
to a forked worker, several at a time. Forking is what makes this
parallel at all -- a ze0 compile is the compiler's own Ruby, and the
GVL lets one thread at a time hold it -- and it is also what bounds
memory, because ruby never gives heap pages back. A worker that grows
past `ZE0_RECYCLE_MB` is closed and another is forked in its place.

`MT_CPU` says how many workers. The default is one per core, or one per
2 GB of the machine's memory when that is fewer: a cold build inside a
worker is what a worker's memory is sized for.

## Run one file, or one example

`rake test` takes files and directories. A bare name is looked up under
`test/`, so the path is optional, and each file is loaded after the
helper its tier loads — which is what a file that reads the compiler's
own load order needs:

```console
$ rake test wasm_test.rb
$ rake test test/unit/wasm_test.rb test/unit/exe_test.rb
$ rake test test/spec/core/string N=/deduplicated/
```

`N=`, `X=` and `A=` mean here what they mean for a whole tier.

The `minitest` command takes the same files, and line numbers besides,
and puts `test` and `lib` on the load path itself. It loads a file
before any helper, so a file that depends on the tier's load order runs
under `rake test` instead:

```console
$ bundle exec minitest test/unit/wasm_test.rb
$ bundle exec minitest test/spec/core/string -n /deduplicated/
$ bundle exec minitest test/spec/core/string/frozen_test.rb:214
```

When a run fails it prints the command to rerun each failure on its
own. `--bisect` finds the pair of examples where one breaks the other.

## Run the units that cover a change

The units are minitest files in `test/unit/`, named after the class
they hold:

```console
$ bundle exec minitest test/unit/hygiene_test.rb test/unit/exe_test.rb
$ rake test:unit N=/Hygiene|Exe|Target/
```

A check that needs wasmtime skips when wasmtime is not installed.

## Accept a new snapshot

Some checks compare against a file in the repository: the HIR dumps,
the disassembly listing, the eval descriptions and the libSystem list.
When your change is meant to change one of these, write it again with
`ZE0_BLESS=1`, then read the diff:

```console
$ ZE0_BLESS=1 rake test:unit N=/Description/
$ git diff rt/ext/os/
```

A change to a kernel def's signature, a struct or a constant under
`rt/kernel/` always needs the description written again.

## Run the specs that cover a change

The specs are in `test/spec/<suite>/<area>/`. Give the directory to
`minitest`, or match on the example's own sentence with `N=`:

```console
$ bundle exec minitest test/spec/core/string
$ rake test:spec N=/frozen/
```

To collect at every allocation, add `GC=stress`. Use it for a change to
the heap, the frames or the roots:

```console
$ rake test:spec N=/blocks/ GC=stress
```

## Run the end-to-end programs

These build whole programs through a real link, in a child of their
own, and hold each binary to ruby's recording:

```console
$ rake test:e2e
$ bundle exec minitest test/e2e -n /socket/
```

## Run for another target

```console
$ rake test:e2e TARGET=wasm32-wasi
$ rake test:spec TARGET=aarch64-linux-musl N=/blocks/
```

A target on its way in is held to what it did rather than to the whole
tier: `test/baselines/<triple>.txt` names the programs it is allowed to
fail. A named program that now passes fails the run, so the file cannot
go stale. See [Whole programs](../reference/test-format.md).

## Check that a literal is still ruby's word

Every literal a spec asserts was lifted from an answer ruby recorded.
`rake oracle` runs each program under the ruby the `.ruby-version`
pins and holds the example to it, compiling nothing:

```console
$ rake 'oracle[test/spec/core/string]'
$ rake oracle
```

## Rewrite a spec file safely

Editing a spec by hand is easy to get subtly wrong, and a wrong edit looks
like a passing run. `Ze0::Reader` reads a file without compiling or running
anything, so what each example *is* — its sentence, its program, its
keywords, the answer it claims — can be compared before and after:

```console
$ rake 'spec:verify[HEAD]'                   # nothing moved since HEAD
$ rake 'spec:verify[HEAD --renames]'         # ... except the sentences
$ rake 'spec:verify[main test/spec/core]'    # one revision, one area
$ rake spec:fingerprint > before.txt         # or keep the digests yourself
```

`--renames` lets a description change and still holds everything else, so a
pass of renaming is checked as tightly as any other edit. Examples are
compared by position, so a reordering or a dropped example is a failure and
not a coincidence. A report names the part that moved — `describe`,
`program`, `keywords` or `answer` — so a pass that meant to touch one of
them can be read back and checked rather than trusted.

## Ask ruby for a literal

A rewrite that changes a program needs a new answer, and the answer never
comes from you. `rake spec:ask` runs a candidate program through the
oracle's own machinery — the same path, the same scrub, the same bare
environment — and prints what ruby said, already shaped as the assertion to
paste:

```console
$ rake 'spec:ask[test/spec/core/thread/thread_test.rb /tmp/fragment.rb]'
_(result).must_answer <<~'OUT'
  42
OUT
```

`-n "<sentence>"` borrows an existing example's keywords, for a fragment
that needs the `files:` or `argv:` its bundle had.

What it cannot see: anything outside an example — file comments, `require`
lines — and a guard is evaluated down one branch, as macOS with everything
available. It proves the examples mean the same, not that the file is
unchanged. Run `rake oracle` beside it, which asks ruby the same question
the spec asks.

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
$ bundle exec rake test:unit             # ze0's internals
$ bundle exec rake test:spec             # Ruby held to ruby
$ bundle exec rake test:spec N=/string/
$ bundle exec rake test:spec GC=stress
$ bundle exec rake test:e2e              # whole programs through a real link
$ bundle exec rake test:spec:slow        # the slowest 25 files
$ bundle exec rake oracle                # every literal re-checked against ruby
$ bundle exec rake stage1 stage2
```
