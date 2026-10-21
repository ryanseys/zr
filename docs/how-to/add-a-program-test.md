# How to add a program test

This guide shows you how to add a program test, how to give a program
its arguments, input and files, and how to split a large program. For
the format of each file, see [Program tests](../reference/program-tests.md).
This guide writes `zr-dev` for `bin/zr-dev`; see
[Tools](../reference/tools.md#tests).

## Add a test

1. Find the directory for the subject of your program, for example
   `test/programs/core/string/case_mapping/` or
   `test/programs/lang/blocks/enumeration/`. A program about the `zr`
   command, the link or the process (ARGV, signals, the flush at exit)
   goes below `test/programs/cli/`.

2. Write the program in a new file. Give the file a name that tells
   the behavior, in lowercase words with `_`:

   ```ruby
   # test/programs/core/string/case_mapping/upcase_keeps_the_receivers_encoding.rb
   puts "ab".upcase.encoding
   ```

3. Get the expected output from the pinned ruby. Never write it yourself:

   ```console
   $ bin/zr-dev expect test/programs/core/string/case_mapping
   core/string/case_mapping/upcase_keeps_the_receivers_encoding.rb: wrote expected
   1 test(s) asked, 1 written
   ```

   `zr-dev expect` writes `upcase_keeps_the_receivers_encoding.rb.expected`.
   If the program also writes to stderr or exits with a status that is
   not 0, it also writes `.rb.err.expected` and `.rb.status`.

4. Run the test:

   ```console
   $ bin/zr-dev test test/programs/core/string/case_mapping/upcase_keeps_the_receivers_encoding.rb
   ```

5. Add the program and each file beside it to git.

If zr refuses the program, the test has an error (`E`) and the message
gives the form. Make zr support the form, or, for a target that cannot
do it, add the test to the target's baseline (see
[Run the tests for another target](run-the-tests.md#run-the-tests-for-another-target)).

## Give the program arguments, input or an environment

Write the files beside the program before you run `zr-dev expect`:

| To give | Write |
|---|---|
| arguments | `foo.rb.args`: the arguments, separated by white space |
| stdin | `foo.rb.stdin`: the bytes |
| environment variables | `foo.rb.env`: one `NAME=value` on each line |
| options for ruby only | `foo.rb.ruby`, such as `-W:no-experimental` |

`zr-dev expect` writes only a test whose program is newer than its
`.expected`. After you change one of these files alone, give `--all`:

```console
$ bin/zr-dev expect --all test/programs/<area>/<subject>/foo.rb
```

## Give the program its own files

Put the files in a `foo.rb.files/` directory. The runner copies the
tree into the run directory, whose root is the directory where the
program runs. The program itself is at its path below `test/programs`.
Thus a file that the program opens by a relative name goes at the root
of `foo.rb.files/`, and a file that must be beside the program (for
`require_relative`) goes in `foo.rb.files/<the program's directory>/`:

```
test/programs/native/requires.rb
test/programs/native/requires.rb.files/native/requires/lib/one.rb
```

A symbolic link in `foo.rb.files/` stays a link. When several tests
need the same files, put them once in `test/fixtures/programs/<name>/`,
and make each `foo.rb.files` a relative link to that directory
(`ln -s ../../../fixtures/programs/etc foo.rb.files`). `zr-dev test
--changed` then runs each test that links it when a file there changes.

## A test that only some machines can run

Write `foo.rb.needs`, with one item on each line. A platform
(`macos`, `linux`, `wasi`) limits the test to those platforms. Another
item, such as `libssl`, is something that the machine must have
(`Zr::Harness::Needs`). A machine that does not meet it skips the test
with the reason.

## When the correct output is different on a platform

Run `zr-dev expect` on that platform. On Linux, it writes
`foo.rb.linux-gnu.expected` and `foo.rb.linux-gnu.err.expected`
(`linux-musl` under musl) when the stdout or the stderr is not the
same as macOS's. A test of that libc then compares with that file.
Record both libcs ([Run the tests](run-the-tests.md)).

## Check that the expected files are still ruby's

```console
$ bin/zr-dev expect --check test/programs/core/string
```

`--check` writes nothing. It lists each test whose files are
different from ruby's output, and fails if there is one.

## Split a large program

A program of more than about a hundred lines usually tests more than
one behavior. To split it:

1. Cut the program into programs. Each program contains the setup that
   the old program had before its part (the requires, the classes, the
   values that print nothing), and one group of statements that makes
   its own output. Do not copy the print statements of an earlier
   group.
2. Get the output of each program with `zr-dev expect`. Do not copy a
   part of the old expected file.
3. Check the split. The outputs of the programs, in order and joined,
   must be the same bytes as the old expected output. If they are
   different, the groups depend on each other: merge two groups and try
   again, or keep the program as one test.
4. If a program needs state that an earlier group made (a file, a
   local), write that state into its setup, and add a comment. Get its
   output from ruby again.
5. Delete the old program and its files.
