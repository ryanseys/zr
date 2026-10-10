# How to debug a wrong answer

This guide shows you how to find why a compiled program does not give
ruby's output. The output is wrong when its stdout, its stderr, its
signal or its exit status is different from what ruby gave.

## See the whole difference

For any Ruby file, `zr diff` runs it under ruby and as a zr binary, and
prints the kind of difference and a diff of each part (stdout, stderr,
the exit status and the signal):

```console
$ zr diff small.rb
```

See [`zr diff`](../reference/cli.md#zr-diff-options-filerb-args).

For a program test, run the one test:

```console
$ ZR_PROGRAMS=core/string/slicing/foo.rb bin/minitest test/programs_test.rb
```

The test compares stdout, stderr, the exit status and the signal
with ruby's, and prints a diff of each part that is different, so
the message tells which one changed. See
[Program tests](../reference/program-tests.md#results).

To run all the tests of an area and see only the failures:

```console
$ ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
```

## Make the program smaller

Copy the program into a file. Remove lines until the difference stays
with the fewest lines. Compare with ruby at each step:

```console
$ ruby small.rb
$ exe/zr run small.rb
```

A small program makes the cause easy to see. When you fix it, keep the
small program as a new program test, as in
[Add your first program test](../tutorials/add-your-first-program-test.md).

## Find which part of zr is wrong

Try these one at a time. Each one removes one part of zr from the
question.

- **The collector.** Collect at every allocation. If the program fails
  only this way, the collector does not find a value:

  ```console
  $ ZR_GC_STRESS=1 ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
  $ ZR_GC_STRESS=1 ./binary
  ```

- **The inline caches.** Turn the caches off, or check each hit against
  a fresh lookup:

  ```console
  $ ZR_MCACHE=0 ./binary
  $ ZR_MCACHE=verify ./binary
  ```

  If the program passes with `ZR_MCACHE=0`, a cache entry is stale.
  `verify` stops at the first wrong entry.

- **The IR.** Check dominance and types in every function when zr
  builds it:

  ```console
  $ ZR_VERIFY=1 exe/zr run small.rb
  ```

- **The platform.** Build the same program as a WASI module. If the
  module is correct and the binary is wrong, the cause is in the
  aarch64 backend or the darwin layer:

  ```console
  $ exe/zr run --emit wasm small.rb
  ```

- **Eval.** For a program that evals, use the tree-walking interpreter
  in place of the eval compiler. If the output changes, the cause is
  in one of the two:

  ```console
  $ ZR_EVAL=walk exe/zr run small.rb
  ```

## Read a crash in lldb

A binary has a symbol for every function. The runtime's functions are
`zr_*`. Run the binary under lldb and read the stack where it stops:

```console
$ lldb ./binary
(lldb) run
(lldb) bt
```

Read the state at the crash. Do not build the program many times to
find the line.

## When the fix is large

Keep the program test. If a target cannot do what the program needs,
add the test to the target's baseline, `test/baselines/<triple>.txt`,
with the reason. A run skips it and prints the reason, so the gap
stays visible, and the run fails when the test passes. See
[Program tests](../reference/program-tests.md#baselines).
