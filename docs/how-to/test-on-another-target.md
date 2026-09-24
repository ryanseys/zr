# How to test on another target

This guide shows you how to run the tests for a target that is not
this host, and what to do with the programs that the target cannot run
correctly yet. For the targets and what each one supports, see
[Targets](../reference/targets.md).

ruby 4.0.6 on macOS gives every expected output. A target is correct
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

A new target does not pass the whole e2e tier at first. Its baseline
file, `test/baselines/<triple>.txt`, lists the whole programs that the
target is allowed to fail, and the reason for each. One line has a
path below `test/`, a tab, and the reason. A line that starts with `#`
is a comment:

```
# wasi has no processes and no signals.
e2e/core/process/process_spawn.rb	spawn() is unimplemented on wasi
e2e/core/process/signal_trap.rb	kill has no wasm form
```

The e2e tier reads the baseline of the target that it runs:

- A program in the baseline that fails is skipped, with the reason.
- A program in the baseline that **passes** makes the run fail, with
  the message `this now passes: take it off test/baselines/<triple>.txt`.
  Thus you learn when a change fixes a program, and the file cannot
  become out of date.

To add a line:

1. Make sure that the target cannot do what the program needs. A line
   is not a place for a bug.
2. Write the path and the reason. Tell what the target does instead.

To remove a line, delete it when the run tells you that the program
passes.

The baselines apply only to the e2e tier. For the spec tier, run a
directory that the target supports, as CI does.

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
$ docker run -d --name alpine -v "$PWD:/zr" -w /zr ruby:4.0.6-alpine sleep infinity
$ docker exec alpine apk add --no-cache build-base git
$ docker exec alpine git config --global --add safe.directory /zr
$ docker exec alpine bundle install
$ docker exec alpine bundle exec rake build
$ docker exec -e TARGET=aarch64-linux-musl alpine bundle exec rake test:e2e
```

These are the commands of the `linux-musl` job in
`.github/workflows/ci.yml`. They need an aarch64 host, for example an
Apple Silicon Mac.
