# How to debug a wrong answer

This guide shows you how to find why a compiled program does not give
ruby's output. The output is wrong when its stdout, its stderr, its
signal or its exit status is different from what ruby gave.

## See the whole difference

Run the one example:

```console
$ bin/test test/spec/core/string/slicing_test.rb -n "/a case/"
```

Minitest prints each part that is different: stdout, stderr, the
signal and the exit status. `must_answer` checks all four, so the
message tells which one changed.

To run all the examples of an area and see only the failures:

```console
$ bin/test test/spec/core/string
```

## Make the program smaller

Copy the program from the example into a file. Remove lines until the
difference stays with the fewest lines. Compare with ruby at each step:

```console
$ ruby small.rb
$ exe/zr run small.rb
```

A small program makes the cause easy to see. When you fix it, keep the
small program as a new example, as in
[Add your first spec](../tutorials/add-your-first-spec.md).

## Find which part of zr is wrong

Try these one at a time. Each one removes one part of zr from the
question.

- **The collector.** Collect at every allocation. If the program fails
  only this way, the collector does not find a value:

  ```console
  $ GC=stress bin/test test/spec/core/string
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

Keep the example in its place, and add a `skip` that tells what it
needs. See [The spec DSL](../reference/spec-dsl.md#a-gap). A run counts
the skipped examples, so the gap stays visible.
