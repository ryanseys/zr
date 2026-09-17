# Add your first spec

In this tutorial, we work in a checkout of ze0. We add one example that
holds ze0 to ruby: we write a small Ruby program, ask ruby what it
says, and assert that what ze0 compiles says the same. This is the loop
behind almost every change to ze0.

You need an Apple Silicon Mac with ruby 4.0.6, the Xcode Command Line
Tools, and git.

## Get the code

Clone the repository and install the development gems:

```console
$ git clone https://github.com/ryanseys/ze0.git
$ cd ze0
$ bundle install
```

Check that the command works:

```console
$ exe/ze0 version
ze0 0.1.0
```

## Ask ruby first

ruby 4.0.6 is the only source of right answers, so we start there. Our
program groups a few words by their length:

```console
$ ruby -e 'words = %w[ruby compiles to native code]
> puts words.map(&:capitalize).join(" ")
> puts words.group_by(&:size).transform_values(&:count).inspect'
Ruby Compiles To Native Code
{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

Those two lines are the answer. We never write one from memory.

## Write the example

Specs live in `test/spec/<suite>/<area>/<subject>_test.rb`. This
program is about enumeration, so it goes in
`test/spec/lang/misc/enumeration_test.rb` — or in whichever file the
area already keeps that subject in.

Add this example inside the file's `describe` block:

```ruby
it "groups words by their length" do
  result = ze0(<<~'RUBY')
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

`ze0` compiles the program with ze0, runs the binary, and hands back
what it said. `must_answer` holds the **whole** answer: stderr must be
empty and the exit status zero unless the example says otherwise. A
program that also wrote a backtrace has not matched.

## Run it

Run the one example, by name:

```console
$ ruby -Ilib -Itest test/spec/lang/misc/enumeration_test.rb -n "/groups words/"
Run options: -n "/groups words/" --seed 12345

# Running:

.

Finished in 0.381226s, 2.6231 runs/s, 10.4924 assertions/s.

1 runs, 4 assertions, 0 failures, 0 errors, 0 skips
```

Four assertions for one example: stdout, stderr, the signal and the
exit status. All four held.

Now run the file, and then its area:

```console
$ bundle exec minitest test/spec/lang/misc/enumeration_test.rb
$ bundle exec minitest test/spec/lang/misc
```

## Hold your literal to ruby

You typed those two lines by hand, so let ruby check them. `rake
oracle` runs each example's program under ruby and holds the example to
what ruby said — it compiles nothing, so it is fast:

```console
$ rake 'oracle[test/spec/lang/misc/enumeration_test.rb]'
test/spec/lang/misc/enumeration_test.rb    12 asked,  0 skipped, 0 apart
12 example(s) asked, 0 skipped, 0 apart from ruby
```

`0 apart` is the point of the whole exercise: the literal in the file
is ruby's word, not yours.

## When ze0 does not answer it yet

An example whose program uses a form ze0 does not compile **skips**,
naming the form. That is the roadmap, not a failure — only a wrong
answer, a crash or a timeout fails. If you find one, leave the example
where it belongs and say what it waits on:

```ruby
it "converts through the carrier's own UTF-8" do
  skip "the carrier tables hold Unicode's code points"
  ...
end
```

The day ze0 answers it, the line comes off, and nothing had to move.

## What you did

You asked ruby, wrote an example that compiles the same program with
ze0, watched all four parts of the answer hold, and had ruby check your
literal afterwards.

Next steps:

- [How to add a spec](../how-to/add-a-spec.md), for arguments, stdin,
  environment and a program's own files
- [How to debug a program that diverges](../how-to/debug-a-program-that-diverges.md)
- [How to run the checks](../how-to/run-the-checks.md)
- [The program format](../reference/test-format.md), for the whole
  programs in `test/e2e/` and `test/bench/`
