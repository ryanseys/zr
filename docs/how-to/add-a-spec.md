# How to add a spec

This guide shows you how to add a spec example, how to change an
existing spec file safely, and how to split a large example. For the
keywords and the format rules, see [The spec DSL](../reference/spec-dsl.md).
This guide writes `zr-dev` for `ruby tool/zr-dev.rb`; see
[Tools](../reference/tools.md#specs-and-recordings).

## Add an example

1. Get the expected output from ruby 4.0.6. Never write it yourself:

   ```console
   $ ruby -e 'puts "ab".upcase.encoding'
   UTF-8
   ```

2. Find the file for the subject of your program, for example
   `test/spec/core/string/case_mapping_test.rb` or
   `test/spec/lang/blocks/enumeration_test.rb`. Add the example to it:

   ```ruby
   it "keeps the receiver's encoding" do
     result = zr(<<~'RUBY')
       puts "ab".upcase.encoding
     RUBY

     _(result).must_answer "UTF-8\n"
   end
   ```

   If the program also writes to stderr or exits with a status that is
   not 0, give that too:

   ```ruby
   _(result).must_answer "out\n", stderr: "stopping here\n", status: 1
   ```

3. Run the example:

   ```console
   $ bin/test test/spec/core/string -n "/keeps the receiver's encoding/"
   ```

4. Check your literal against ruby:

   ```console
   $ ruby tool/zr-dev.rb oracle test/spec/core/string
   ```

5. Check the format of the file:

   ```console
   $ ruby tool/zr-dev.rb spec check test/spec/core/string
   ```

   `spec check` with a path compares sentences only in that path. Run
   `zr-dev spec check` without a path before you push many new sentences,
   because a sentence must be unique in the whole suite.

If zr refuses the program, the example skips and gives the form. That
is not a failure. A wrong output, a crash or a timeout is a failure.

## Get the expected output for a candidate program

`zr-dev spec ask` runs a program the same way as `zr-dev oracle`, with
the same path, cleanup and environment. It prints the assertion to paste:

```console
$ ruby tool/zr-dev.rb spec ask test/spec/core/thread/thread_test.rb /tmp/fragment.rb
_(result).must_answer <<~'OUT'
  42
OUT
```

Add `-n "<sentence>"` to use the keywords (`files:`, `argv:`) of an
existing example.

## Change a spec file safely

A wrong edit to a spec can look like a passing run.
`zr-dev spec verify` reads each example without a compile or a run.
It compares the sentence, program, keywords and expected output of
each example with the same example at a revision:

```console
$ ruby tool/zr-dev.rb spec verify HEAD                  # nothing changed since HEAD
$ ruby tool/zr-dev.rb spec verify HEAD --renames        # only the sentences changed
$ ruby tool/zr-dev.rb spec verify main test/spec/core   # one revision, one area
$ ruby tool/zr-dev.rb spec fingerprint > before.txt     # or keep the digests yourself
```

It compares examples by position, so an example that moved or that you
deleted is a failure. A report gives the part that changed:
`describe`, `program`, `keywords` or `answer`.

`spec:verify` does not see anything outside an example, such as a
comment or a `require` line. It evaluates a guard for macOS with all
features. Run `zr-dev oracle` too.

## Split a large example

A program of more than about a hundred lines usually tests more than
one behavior. To split it:

1. Cut the program into fragments. Each fragment contains the setup
   that the program had before it (the requires, the classes, the
   values that print nothing), and one group of statements that makes
   its own output. Do not copy the print statements of an earlier
   group.
2. Get the output of each fragment with `zr-dev spec ask`. Do not copy a
   part of the old literal.
3. Check the split. The outputs of the fragments, in order and joined,
   must be the same bytes as the old expected output. If they are
   different, the groups depend on each other: merge two groups and try
   again, or keep the program as one example.
4. If a fragment needs state that an earlier group made (a file, a
   local), write that state into the fragment's setup, and add a
   comment. Get its output from ruby again.
5. Run `zr-dev oracle` on the file.

`zr-dev spec split <path>` lists the examples that can be split.

## When zr cannot pass the example yet

Keep the example in its place, and add a `skip` that tells what it
needs. See [The spec DSL](../reference/spec-dsl.md#a-gap).

## A whole program

A program that needs a real link, or a large graph of required files,
is not a spec. Put it in `test/e2e/<suite>/<area>/` with its recording.
See [Whole programs](../reference/test-format.md).
