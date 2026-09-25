# Add your first spec

In this tutorial, we work in a checkout of zr. We add one example that
checks zr against ruby: we write a small Ruby program, get ruby's
output, and assert that the program that zr compiles gives the same
output. Almost every change to zr starts with this loop.

You need an Apple Silicon Mac with ruby 4.0.6 and git.

## Get the code

Clone the repository and set it up:

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup
```

`bin/setup` installs the gems and builds the runtime. The first build
takes a few minutes.

Check that the command works:

```console
$ exe/zr version
zr 0.1.0
```

## Get the output from ruby first

ruby 4.0.6 is the only source of expected outputs, so we start there.
Our program puts a few words into groups by their length:

```console
$ ruby -e 'words = %w[ruby compiles to native code]
> puts words.map(&:capitalize).join(" ")
> puts words.group_by(&:size).transform_values(&:count).inspect'
Ruby Compiles To Native Code
{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

These two lines are the expected output. We never write one from
memory.

## Write the example

Specs are in `test/spec/<suite>/<area>/<subject>_test.rb`. This
program is about enumeration, so it goes in
`test/spec/lang/blocks/enumeration_test.rb`.

Add this example inside the file's `describe` block:

```ruby
it "groups words by their length" do
  result = zr(<<~'RUBY')
    words = %w[ruby compiles to native code]
    puts words.map(&:capitalize).join(" ")
    puts words.group_by(&:size).transform_values(&:count).inspect
  RUBY

  _(result).must_answer <<~'OUT'
    Ruby Compiles To Native Code
    {4 => 2, 8 => 1, 2 => 1, 6 => 1}
  OUT
end
```

`zr` compiles the program with zr, runs the binary, and returns what
it wrote. `must_answer` checks the **whole** output: stderr must be
empty and the exit status must be zero, unless the example gives other
values. A program that also wrote a backtrace does not match.

## Run it

Run the one example, by name:

```console
$ bin/test test/spec/lang/blocks/enumeration_test.rb -n "/groups words/"
Run options: -n "/groups words/" --seed 12345

# Running:

.

Finished in 0.381226s, 2.6231 runs/s, 10.4924 assertions/s.

1 runs, 4 assertions, 0 failures, 0 errors, 0 skips
```

One example makes four assertions: stdout, stderr, the signal and the
exit status. All four passed.

Now run the file, and then its area:

```console
$ bin/test test/spec/lang/blocks/enumeration_test.rb
$ bin/test test/spec/lang/blocks
```

## Check your literal against ruby

You typed the two lines by hand, so let ruby check them. The oracle
(`ruby tool/zr-dev.rb oracle`) runs the program of each example under
ruby and compares the output with the example's literal. It compiles nothing, so it is fast:

```console
$ ruby tool/zr-dev.rb oracle test/spec/lang/blocks/enumeration_test.rb
test/spec/lang/blocks/enumeration_test.rb    12 asked,  0 skipped, 0 apart
12 example(s) asked, 0 skipped, 0 apart from ruby
```

`0 apart` is the important result: the literal in the file is ruby's
output, not yours.

## When zr cannot pass it yet

If zr does not support a form that the program uses, the example
**skips**, and the message gives the form. That is not a failure: only
a wrong output, a crash or a timeout fails. If zr gives a wrong output
and the fix is large, keep the example in its place and tell what it
needs:

```ruby
it "converts through the carrier's own UTF-8" do
  skip "the carrier tables hold Unicode's code points"
  ...
end
```

When zr can pass it, delete the `skip` line.

## What you did

You got the output from ruby, wrote an example that compiles the same
program with zr, saw all four parts of the output pass, and let ruby
check your literal.

Next steps:

- [How to add a spec](../how-to/add-a-spec.md) and
  [The spec DSL](../reference/spec-dsl.md), for arguments, stdin, the
  environment and a program's own files
- [How to debug a wrong answer](../how-to/debug-a-wrong-answer.md)
- [How to run the tests](../how-to/run-the-tests.md)
- [Whole programs](../reference/test-format.md), for the programs in
  `test/e2e/` and `benchmark/`
