# How to run the tests

This guide shows you how to run zr's tests in a checkout. Run the
smallest set of tests that covers your change. Run all the tests before
you open a pull request.

For the full list of rake tasks, `zr-dev` commands and test variables,
see [Tools](../reference/tools.md). This guide writes `zr-dev` for
`ruby tool/zr-dev.rb`. To learn how a
tier runs, see [How the tests run](../explanation/how-the-tests-run.md).

## Before you start

Set up the checkout one time:

```console
$ bin/setup
```

`bin/setup` installs the gems and builds the runtime for this host.
The first build takes a few minutes. `bin/test` builds the runtime
again when a change under `lib/` or `runtime/` makes it out of date.
To build the runtime without a test run:

```console
$ rake build
```

The WASI runtime is a different build, of about five minutes. Build it
before you run the tests that make WASI modules:

```console
$ rake build:wasm
$ rake build:all        # this host and wasm32-wasi; needs about 12 GB of memory
```

Until you build it, the unit tests that make WASI modules skip, and
tell you why. They also skip when wasmtime is not installed.

## Run all the tests

```console
$ bin/test
```

This runs the three tiers, one after the other: `test/unit`, then
`test/spec`, then `test/e2e`. `rake test` does the same. `rake` runs
`rake lint` first, then the tests.

## Run one tier, one directory or one file

Give `bin/test` one or more paths:

```console
$ bin/test test/unit
$ bin/test test/spec/core/string
$ bin/test test/unit/wasm_test.rb test/unit/exe_test.rb
$ bin/test wasm_test.rb
```

A bare file name is found below `test/`. `rake test:unit`,
`rake test:spec` and `rake test:e2e` run one tier.

## Run some examples

Put minitest options after the paths, or set `N` or `X`. A rake
task also takes them as arguments:

```console
$ bin/test test/spec -n /deduplicated/
$ N='/Hygiene|Exe|Target/' bin/test test/unit
$ X=/encoding/ bin/test test/spec/core/string
$ rake test:spec N=/frozen/
```

To run the example at one line, use minitest's own command:

```console
$ bundle exec minitest test/spec/core/string/frozen_test.rb:214
```

`minitest` loads the file before the tier's helper. A file that needs
the tier's load order runs only under `bin/test`.

When a run fails, it prints a command that runs each failure again
alone.

## Run the specs that a change can reach

```console
$ ruby tool/zr-dev.rb affected
$ ruby tool/zr-dev.rb affected --base origin/main
$ ruby tool/zr-dev.rb affected --dry-run
```

`zr-dev affected` reads the diff against `main`, or against `--base`.
It runs the specs that the changed files can reach, with `bin/test`.
For a file under `runtime/core`, these are the directory of its class
and every spec that uses the class name. For a change to the compiler,
the kernel or the test support, it runs all the specs. `--dry-run`
prints the spec paths and runs nothing.

## Collect at every allocation

Add `GC=stress` after a change to the heap, the frames or the roots:

```console
$ GC=stress bin/test test/spec/lang/blocks
$ rake test:spec N=/blocks/ GC=stress
```

A value that the collector does not find then fails at once.

## Accept a new snapshot

Some tests compare output with a file in the repository: the HIR dumps,
the disassembly listing, the descriptions and the libSystem list. If
your change must change one of these files, write it again with
`ZR_BLESS=1`, then read the diff:

```console
$ ZR_BLESS=1 bin/test test/unit/description_test.rb
$ git diff runtime/ext/os/
```

A change to the signature of a kernel def, or to a struct or a constant
under `runtime/kernel/`, always changes the description.

## Check that a literal is still ruby's output

`zr-dev oracle` runs each example's program under ruby 4.0.7 and checks
the example's expected output against it. It compiles nothing, so it
is fast:

```console
$ ruby tool/zr-dev.rb oracle test/spec/core/string
$ ruby tool/zr-dev.rb oracle
```

## Run the tests for another target

```console
$ TARGET=wasm32-wasi bin/test test/e2e
```

See [How to test on another target](test-on-another-target.md).

## Check the bootstrap

Run these after a change to the compiler or to the kernel's layouts:

```console
$ ruby tool/zr-dev.rb stage 1
$ ruby tool/zr-dev.rb stage 2
```

`zr-dev stage 2` takes about ten minutes and 5 GB of memory, so run it
alone. See [Bootstrapping](../explanation/bootstrapping.md).

## See the progress of a long run

A tier writes its progress to `tmp/test-progress.txt`. From another
terminal:

```console
$ ruby tool/zr-dev.rb progress
```

## Find the slow tests

```console
$ SLOW=1 bin/test test/spec
$ SLOW=1 rake test:spec
```

Both also report the 25 slowest files and the 20 slowest examples.

## Check the code style

```console
$ rake lint
```
