# How to test on another target

This guide shows you how to run the tests for a target that is not
this host, and what to do with the programs that the target cannot run
correctly yet. For the targets and what each one supports, see
[Targets](../reference/targets.md).

ruby 4.0.7 on macOS gives every expected output. A target is correct
when it gives the same output.

## Run the tests for a target

Set `TARGET` to the triple:

```console
$ TARGET=wasm32-wasi bin/test test/e2e
$ rake test:spec TARGET=aarch64-linux-musl N=/blocks/
```

The tests build each program for that target and start it as that
target starts: a binary on its own host, a WASI module under wasmtime.

For `wasm32-wasi`, build the WASI runtime first (`rake build:wasm`),
and install [wasmtime](https://wasmtime.dev).

## Let a target fail what it cannot do yet

A new target does not pass every test at first. Its baseline file,
`test/baselines/<triple>.txt`, lists the e2e programs and the spec
examples that the target is allowed to fail, and the reason for each.
One line has a key, a tab, and the reason. The key of a program is its
path below `test/`. The key of a spec example is its file below `test/`,
`: `, and its description. A line that starts with `#` is a comment:

```
# wasi has no processes and no signals.
e2e/core/process/process_spawn.rb	spawn() is unimplemented on wasi
spec/core/hash/hash_test.rb: dir chdir block form restores the previous directory	chdir has no wasm form
```

The e2e and spec tiers read the baseline of the target that they run:

- A test in the baseline that fails is skipped, with the reason.
- A test in the baseline that **passes** makes the run fail, with the
  message `this now passes: take it off test/baselines/<triple>.txt`.
  Thus you learn when a change fixes a test, and the file cannot become
  out of date.

To add a line:

1. Make sure that the target cannot do what the test needs. A line is
   not a place for a bug.
2. Write the key and the reason. Tell what the target does instead.

To remove a line, delete it when the run tells you that the test passes.

The spec tier is large, so on another target run the directories that
CI runs, and give the baseline the examples in them that fail.

## When the correct output is different on a target

A spec example gives the stdout of each platform that is different:

```ruby
_(result).must_answer "arm64-darwin24\n", linux: "aarch64-linux-musl\n", wasi: "wasm32-wasi\n"
```

See [The spec DSL](../reference/spec-dsl.md).

A whole program in `test/e2e/` has no such form. A program whose output
depends on the target usually tests two things. Split it into two
programs.

## Run the Linux tests in the container that CI uses

```console
$ docker run -d --name alpine -v "$PWD:/zr" -w /zr ruby:4.0.7-alpine sleep infinity
$ docker exec alpine apk add --no-cache build-base git
$ docker exec alpine git config --global --add safe.directory /zr
$ docker exec alpine bundle install
$ docker exec alpine bundle exec rake build
$ docker exec -e TARGET=aarch64-linux-musl alpine bundle exec rake test:e2e
```

These are the commands of the `linux-musl` job in
`.github/workflows/ci.yml`. They need an aarch64 host, for example an
Apple Silicon Mac.
