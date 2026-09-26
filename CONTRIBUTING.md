# Contributing to zr

Thank you for helping. This page tells you how to start. The guides in
[`docs/`](docs/README.md) have the details.

## Set up

You need ruby 4.0.7 (see `.ruby-version`; for example
`mise install ruby@4.0.7` or `rbenv install 4.0.7`) on an Apple
Silicon Mac with 16 GB of memory or more. The first `bin/setup` takes
some minutes, and a full `bin/test` takes much longer; start with the
tests near your change. [wasmtime](https://wasmtime.dev) is optional;
without it, the tests that run WebAssembly modules skip.

On Linux, you can work on the `wasm32-wasi` target:
`rake build:all`, then `TARGET=wasm32-wasi bin/test <paths>`. See
[How to test on another target](docs/how-to/test-on-another-target.md).

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup     # installs the gems and builds the runtime (a few minutes)
$ bin/test      # runs every tier: unit, spec, e2e
```

## Make a change

1. Write a spec that shows the change: see
   [Add your first spec](docs/tutorials/add-your-first-spec.md).
2. Change the compiler (`lib/`) or the runtime (`runtime/`).
3. Run the tests that cover the change: `bin/test --changed`, or a
   path such as `bin/test test/spec/core/string`. Then run `bin/test`
   before you open a pull request. A full run takes a long time and
   much memory; `MT_CPU=4` uses fewer workers. See
   [How to run the tests](docs/how-to/run-the-tests.md).
4. Add a line to `CHANGELOG.md` under `[Unreleased]`.

ruby 4.0.7 is the reference: a compiled program must print what ruby
prints, byte for byte. When zr cannot do that for a form, it refuses the
form by name. See [The contract](docs/explanation/the-contract.md).

## Style

- Write idiomatic Ruby, and fix zr when zr makes it slow. See
  [How zr's Ruby is written](docs/explanation/ruby-style.md).
- Plain English in comments and docs: short sentences, active voice,
  one term for one concept. The [glossary](docs/reference/glossary.md)
  lists the terms.
- A comment says why, not what the code already says.
- Test names say what they check: `test_<subject>_<condition>_<result>`.
- A spec sentence (`it "..."`) says what the program does, in the
  present tense: `a frozen String raises FrozenError on <<`. It names no
  issue number.
- `bundle exec rake lint` runs RuboCop's Lint cops.

## Report a security problem

See [SECURITY.md](SECURITY.md).
