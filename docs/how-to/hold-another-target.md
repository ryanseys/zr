# How to hold another target

This guide shows you how to run the tests for a target that is not the
one you are sitting at, and what to do about the parts of it that do
not pass yet.

ruby 4.0.6 on macOS is the oracle, and every recorded answer is its
answer. A target is right when it gives that same answer:

```console
$ rake test:e2e TARGET=aarch64-linux-musl
$ rake test:spec TARGET=wasm32-wasi N=/blocks/
```

`TARGET` names a triple to build for, and the run starts what it built
the way that triple is started — a binary on its own host, a module
under wasmtime.

## Let a target fail what it cannot do yet

A target on its way in is held to what it did rather than to the whole
tier. `test/baselines/<triple>.txt` names the programs it is allowed to
fail and why, one path and reason a line, separated by a tab:

```
# wasi has no processes and no signals.
e2e/core/process/process_spawn.rb	spawn() is unimplemented on wasi
e2e/core/process/signal_trap.rb	kill has no wasm form
```

A named program that fails is skipped with its reason. A named program
that **passes** fails the run and says to take it off the file, so when
a change fixes one you learn about it rather than having to look.

Write a row only for something the target genuinely cannot do, and say
what it does instead. A row is not a place to put a bug.

## When a target's answer is right but different

A spec example says so beside its answer:

```ruby
it "names the platform" do
  _(ze0(%(puts RUBY_PLATFORM))).must_answer "arm64-darwin24\n",
                                            linux: "aarch64-linux-musl\n",
                                            wasi: "wasm32-wasi\n"
end
```

A platform the call does not name answers what macOS answers. See
[How to add a spec](add-a-spec.md).

An end-to-end program has no such form, because none has needed one: a
program whose answer depends on the target is nearly always asking two
questions, and splitting it is better than recording it twice.

## Run the Linux tests in the container CI uses

```console
$ docker run -d --name alpine -v "$PWD:/ze0" -w /ze0 ruby:4.0.6-alpine sleep infinity
$ docker exec alpine apk add --no-cache build-base git
$ docker exec alpine bundle install
$ docker exec -e TARGET=aarch64-linux-musl alpine bundle exec rake test:e2e
```
