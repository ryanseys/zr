# Add your first program test

In this tutorial, we work in a checkout of zr. We add one test that
checks zr against ruby: we write a small Ruby program, let ruby write
its output beside it, and see that the program that zr compiles gives
the same output. Almost every change to zr starts with this loop.

You need an Apple Silicon Mac with git, and the ruby that zr's
`.ruby-version` names.

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
zr 0.1.0 (for ruby 4.x.y)
```

## Write the program

A program test is a plain Ruby file under `test/programs/`. Our program
puts a few words into groups by their length. It is about enumeration
with blocks, so it goes in `test/programs/lang/blocks/enumeration/`.

Make the file
`test/programs/lang/blocks/enumeration/groups_words_by_their_length.rb`:

```ruby
words = %w[ruby compiles to native code]
puts words.map(&:capitalize).join(" ")
puts words.group_by(&:size).transform_values(&:count).inspect
```

Nothing else goes in the file: no test class and no assertion. Run it
with ruby, as you run any program:

```console
$ ruby test/programs/lang/blocks/enumeration/groups_words_by_their_length.rb
Ruby Compiles To Native Code
{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

## Let ruby write the expected output

The pinned ruby is the only source of expected outputs, so we never type
one. `zr-dev expect` runs the program under ruby and writes what it
printed beside the program:

```console
$ bin/zr-dev expect test/programs/lang/blocks/enumeration
lang/blocks/enumeration/groups_words_by_their_length.rb: wrote expected
1 test(s) asked, 1 written
```

It asks only a program that has no expected output, or whose expected
output is older than the program. Look at the new file:

```console
$ cat test/programs/lang/blocks/enumeration/groups_words_by_their_length.rb.expected
Ruby Compiles To Native Code
{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

The program wrote nothing to stderr and exited with status 0, so there
is no `.rb.err.expected` file and no `.rb.status` file.

## Run it

Run the one test. Give its path below `test/programs` in
`ZR_PROGRAMS`:

```console
$ ZR_PROGRAMS=lang/blocks/enumeration/groups_words_by_their_length.rb bin/minitest test/programs_test.rb
6 test worker(s) on 12 cores and 16 GB (MT_CPU sets the number)
Run options: --seed 4242

# Running:

.

Finished in 2.96s, 0.34 runs/s, 0.34 assertions/s.

1 runs, 1 assertions, 0 failures, 0 errors, 0 skips
```

The number of workers, the seed and the times are different on your
machine. The `.` is our test. zr built the program, ran the binary, and
compared all of its output with ruby's: the stdout, the stderr, and the
exit status. A program that also wrote a backtrace does not pass.

Now run the directory, and then its area:

```console
$ ZR_PROGRAMS=lang/blocks/enumeration bin/minitest test/programs_test.rb
$ ZR_PROGRAMS=lang/blocks bin/minitest test/programs_test.rb
```

## See a failure

Change the second line of the `.expected` file by hand, for example
`4 => 2` to `4 => 3`, and run the test again. The mark is `F`, and
minitest prints the name of the test and the difference:

```
ProgramsTest#test_lang/blocks/enumeration/groups_words_by_their_length.rb
--- expected stdout
+++ actual stdout
 Ruby Compiles To Native Code
-{4 => 3, 8 => 1, 2 => 1, 6 => 1}
+{4 => 2, 8 => 1, 2 => 1, 6 => 1}
```

Now let ruby correct the file. `--check` tells you that the file is
not ruby's, and `--all` writes it again:

```console
$ bin/zr-dev expect --check test/programs/lang/blocks/enumeration
$ bin/zr-dev expect --all test/programs/lang/blocks/enumeration
```

Run the test again. It passes.

## When zr cannot pass it yet

If zr does not support a form that the program uses, the test has an
error (`E`), and the message gives the form. The fix is in zr. A
target that cannot do what the program needs lists the test in its
baseline, with the reason.

## What you did

You wrote a plain Ruby program, let ruby write its expected output,
saw zr give the same output, and saw how a difference looks.

Next steps:

- [How to add a program test](../how-to/add-a-program-test.md) and
  [Program tests](../reference/program-tests.md), for arguments,
  stdin, the environment and a program's own files
- [How to debug a wrong answer](../how-to/debug-a-wrong-answer.md)
- [How to run the tests](../how-to/run-the-tests.md)
