# Add your first corpus case

In this tutorial, we work in a checkout of ze0. We add one test program
to the corpus, record ruby's answer in it, and check that ze0 gives the
same answer. This is the loop behind almost every change to ze0.

You need an Apple Silicon Mac with ruby 4.0.6, the Xcode Command Line
Tools, and git.

## Get the code

Clone the repository and install the development gems:

```console
$ git clone https://github.com/ryanseys/ze0.git
$ cd ze0
$ bundle install
```

Check that the checkout's command works:

```console
$ bin/ze0 version
ze0 0.1.0
```

`bin/ze0` is the checkout's version of the `ze0` command. It has the
gem's commands, and some more that need the tests and tools in the
repository.

## Write a program

The corpus is a directory of Ruby programs under `test/`. Each program
is one file. We add one to `test/lang/misc/`.

Write this to `test/lang/misc/words_group_by_size.rb`:

```ruby
words = %w[ruby compiles to native code]
puts words.map(&:capitalize).join(" ")
puts words.group_by(&:size).transform_values(&:count).inspect
```

## Record ruby's answer

A corpus program carries ruby's answer at its bottom, after `__END__`.
You never write that answer by hand. A tool runs ruby and writes it:

```console
$ ruby tools/record.rb lang/misc/words_group_by_size.rb
recorded lang/misc/words_group_by_size.rb (exit 0)
```

Open the file again. It now ends like this:

```ruby
words = %w[ruby compiles to native code]
puts words.map(&:capitalize).join(" ")
puts words.group_by(&:size).transform_values(&:count).inspect

__END__
Ruby Compiles To Native Code
{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

Notice that ruby stops reading the file at `__END__`. The recording
costs the program nothing.

## Run the case with ze0

Run the case through ze0 with `tools/test.rb`. It compiles the program,
runs the binary, and compares its output with the recording:

```console
$ ruby tools/test.rb lang/misc/words_group_by_size.rb

case lang/misc/words_group_by_size.rb
  program    args=[] env={} stdin=-
  build        0.4s ok
  ...
  run          0.0s exit 0
  status     exit 0, the same
  stdout     2 line(s), the same
  stderr     0 line(s), the same
  verdict    matched
```

The verdict is `matched`: the binary said exactly what ruby said.

## Run it as part of the corpus

`tools/test.rb` shows one case in detail. `bin/ze0 test` runs many
cases and counts them. Give it part of a case's name:

```console
$ bin/ze0 test lang/misc/words
ze0 test: 1 program(s)

matched   1
refused   0
backend   0
skipped   0
diverged  0
crashed   0
timeout   0
  every row: tmp/sweep.txt
```

Now run the whole directory the case is in:

```console
$ bin/ze0 test lang/misc/
```

Each program goes into one bucket. `matched` is a pass. `diverged`,
`crashed` and `timeout` are defects.

## What you did

You added a program to the corpus, recorded ruby's answer in it, and
saw ze0 match that answer, first for one case and then for its
directory.

When ze0 does not match a program, the same tools show you where the
two answers part. Next steps:

- [How to debug a program that diverges](../how-to/debug-a-program-that-diverges.md)
- [How to run the checks](../how-to/run-the-checks.md)
- [The test format](../reference/test-format.md), for arguments, stdin,
  environment and platform sections.
