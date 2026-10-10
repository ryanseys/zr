# How to test on another target

This guide shows you how to run the tests for a target that is not
this host, and what to do with the programs that the target cannot run
correctly yet. For the targets and what each one supports, see
[Targets](../reference/targets.md).

ruby 4.0.7 on macOS gives every expected output. A target is correct
when it gives the same output.

## Run the tests for a target

Set `ZR_TARGET` to the triple:

```console
$ ZR_TARGET=wasm32-wasi ZR_PROGRAMS=cli bin/minitest test/programs_test.rb
$ ZR_TARGET=aarch64-linux-musl ZR_PROGRAMS=lang/methods bin/minitest test/programs_test.rb
```

The tests build each program for that target and start it as that
target starts: a binary on its own host, a WASI module under wasmtime.

For `wasm32-wasi`, build the WASI runtime first (`rake build:wasm`),
and install [wasmtime](https://wasmtime.dev).

## Let a target fail what it cannot do yet

A new target does not pass every test at first. Its baseline file,
`test/baselines/<triple>.txt`, lists the program tests that the
target is allowed to fail, and the reason for each. The host,
`aarch64-apple-darwin`, has a baseline too. One line has a key, a tab,
and the reason. The key is the path of the program below
`test/programs`. A line that starts with `#` is a comment:

```
# wasi has no processes and no signals.
cli/core/process/process_spawn.rb	spawn() is unimplemented on wasi
core/hash/dir_chdir_block_form_restores_the_previous_directory.rb	chdir has no wasm form
```

The program tests read the baseline of the target that they run
(`test/support/baseline.rb`):

- A test in the baseline that fails, or that zr refuses, is skipped,
  with the reason.
- A test in the baseline that **passes** makes the run fail, with the
  message `this now passes: take it off test/baselines/<triple>.txt`.
  Thus you learn when a change fixes a test, and the file cannot become
  out of date.

To add a line:

1. Make sure that the target cannot do what the test needs. A line is
   not a place for a bug.
2. Write the key and the reason. Tell what the target does instead.

To remove a line, delete it when the run tells you that the test passes.

There are thousands of program tests, so on another target run the
directories that CI runs (`.github/workflows/ci.yml`): `ZR_PROGRAMS=cli`
and a slice of the language and core areas. Give the baseline the
tests in them that fail.

## When the correct output is different on a target

A program test can have the stdout of a platform in its own file,
`foo.rb.linux.expected` or `foo.rb.wasi.expected`. A test on that
platform compares with that file, and a test on another platform with
`foo.rb.expected`. On Linux, `zr-dev expect` writes
`foo.rb.linux.expected` when the stdout is not the same as
`foo.rb.expected`. See [Program tests](../reference/program-tests.md).

A program whose output depends on the target usually tests two
things. Split it into two programs.

A test that a platform cannot run at all gives the platforms that can
run it in `foo.rb.needs` (`macos`, `linux`, `wasi`).

## Run the Linux tests in the container that CI uses

```console
$ docker run -d --name alpine -v "$PWD:/zr" -w /zr ruby:4.0.7-alpine sleep infinity
$ docker exec alpine apk add --no-cache build-base git
$ docker exec alpine git config --global --add safe.directory /zr
$ docker exec alpine bundle config set --global without development
$ docker exec alpine bundle install
$ docker exec alpine ruby tool/install_reference_gems.rb
$ docker exec alpine bundle exec rake build
$ docker exec -e ZR_TARGET=aarch64-linux-musl -e ZR_PROGRAMS=cli alpine bin/minitest test/programs_test.rb
```

These are the commands of the `linux-musl` job in
`.github/workflows/ci.yml`. `tool/install_reference_gems.rb` installs the
gems that ruby's side of a program test reads (`tmp/reference`). They need an aarch64 host, for example an
Apple Silicon Mac.
