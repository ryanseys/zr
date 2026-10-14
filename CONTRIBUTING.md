# Contributing to zr

Thank you for helping. This page tells you how to start. The guides in
[`docs/`](docs/README.md) have the details.

## Set up

You need the ruby that `.ruby-version` names (for example
`mise install ruby@$(cat .ruby-version)` or
`rbenv install $(cat .ruby-version)`) on an Apple
Silicon Mac with 16 GB of memory or more. The first `bin/setup` takes
some minutes, and a full `bin/minitest` takes much longer; start with the
tests near your change. [wasmtime](https://wasmtime.dev) is optional;
without it, the tests that run WebAssembly modules skip.

On Linux, you can work on the `wasm32-wasi` target:
`rake build:wasm`, then `ZR_TARGET=wasm32-wasi bin/minitest <paths>`. See
[How to test on another target](docs/how-to/test-on-another-target.md).

```console
$ git clone https://github.com/ryanseys/zr.git
$ cd zr
$ bin/setup     # installs the gems and builds the runtime (a few minutes)
$ bin/minitest  # runs every test: unit, programs, ext
```

## Make a change

1. Write a program test that shows the change: see
   [Add your first program test](docs/tutorials/add-your-first-program-test.md).
2. Change the compiler (`lib/`) or the runtime (`lib/zr/runtime/`).
3. Run the tests that cover the change: `bin/zr-dev test --changed`, or
   some programs such as `bin/zr-dev test test/programs/core/string`. Then
   run `bin/zr-dev test` before you open a pull request. A full run takes a
   long time and much memory; `-j 4` uses fewer workers. See
   [How to run the tests](docs/how-to/run-the-tests.md).
4. When a user sees the change (a feature, a changed behavior or a
   fix), add a line to `CHANGELOG.md` under `[Unreleased]`. A change to
   the tests, the tools or the docs gets no line.

The pinned ruby is the reference: a compiled program must print what ruby
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
- A program test's file name says what the program does, in the
  present tense: `a_frozen_string_raises_frozen_error_on_append.rb`. It
  names no issue number.
- `bundle exec rake lint` runs RuboCop: the Lint cops and the cops that
  `.rubocop.yml` adds, each with its reason.
- `bin/steep check` runs Steep on every file of the compiler and on the
  kernel. Annotate
  methods with inline RBS (`#: (Integer) -> String`). A declaration that
  inline RBS cannot type (a `Struct` or `Data` record, a
  `module_function` module) has `# @rbs skip` above it and its types in
  `sig/zr/`. To check a file more strictly, name it in a stricter level
  of the `Steepfile`.
- `COVERAGE=1 bin/minitest <paths>` measures the line and branch coverage of
  `lib/` and writes `tmp/coverage/index.html`. It gates nothing.

## Report a security problem

See [SECURITY.md](SECURITY.md).

## Conduct

This project follows the [code of conduct](CODE_OF_CONDUCT.md).
