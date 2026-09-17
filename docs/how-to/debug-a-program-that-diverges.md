# How to debug a program that diverges

This guide shows you how to find why a compiled program does not answer
what ruby answered. A program *diverges* when its output, its stderr or
its exit status differs from the recording.

## See the whole difference

Run the one example, by name, in a process of its own:

```console
$ ruby -Ilib -Itest test/spec/core/string/slicing_test.rb -n "/a case/"
```

Minitest prints every line where the two answers part, one part at a
time: stdout, stderr, the signal and the exit status. `must_answer`
asserts all four, so the message names which one moved.

To run everything an area holds, and see only what failed:

```console
$ rake test:spec FILTER=string
```

## Make the program smaller

Copy the program out of the example into a scratch file, and remove
lines until the difference stays with the fewest lines. Compare with
ruby at each step:

```console
$ ruby small.rb
$ exe/ze0 run small.rb
```

A small program makes the cause easy to see. When you fix it, keep the
small program as a new example, as in
[Add your first spec](../tutorials/add-your-first-spec.md).

## Find which part of ze0 is wrong

Try these one at a time. Each one takes one part of ze0 out of the
question.

- **The collector.** Run with a collection at every allocation. A
  program that fails only this way has a value the collector does not
  see:

  ```console
  $ rake test:spec FILTER=string GC=stress
  $ ZR_GC_STRESS=1 ./binary
  ```

- **The method caches.** Turn the call-site caches off, or check each
  hit against a fresh lookup:

  ```console
  $ ZR_MCACHE=0 ./binary
  $ ZR_MCACHE=verify ./binary
  ```

  A program that passes with `ZR_MCACHE=0` has a stale cache entry.
  `verify` stops at the first wrong one.

- **The IR.** Check dominance and types in every function as it is
  built:

  ```console
  $ ZE0_VERIFY=1 exe/ze0 run small.rb
  ```

- **The platform.** Build the same program as a wasm module. If the
  module is right and the binary is wrong, the cause is in the aarch64
  backend or the darwin layer:

  ```console
  $ exe/ze0 build small.rb -o small.wasm --emit wasm && wasmtime small.wasm
  ```

## Read a crash in lldb

A binary has symbols for every function, named `zr_*` for the runtime.
Run it under lldb and read the stack where it stops:

```console
$ lldb ./binary
(lldb) run
(lldb) bt
```

Read the state at the crash. Do not rebuild the program again and again
to find the line.

## When ze0 cannot do it yet

If the fix is large, leave the example where it belongs and say what it
waits on:

```ruby
it "converts through the carrier's own UTF-8" do
  skip "the carrier tables hold Unicode's code points"
  ...
end
```

A skipped example is counted and named at the end of a run, so the gap
stays visible. The day ze0 answers it, the line comes off -- and nothing
was moved, so nothing has to be moved back.
