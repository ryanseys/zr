# zr documentation

The documentation has four parts. Each part is for a different need.

## Tutorials: start here

Lessons that take you, step by step, to a result.

- [Compile your first program](tutorials/compile-your-first-program.md):
  install zr, and build one Ruby file as a binary and as a WebAssembly
  module.
- [Add your first spec](tutorials/add-your-first-spec.md): work in a
  checkout, get the expected output from ruby, and see zr give the same
  output.

## How-to guides: do a task

Steps for a goal that you already have.

- [How to install zr](how-to/install.md): get ruby 4.0.7, install
  zr, and fix the problems that an install can have
- [How to use a library or a gem](how-to/use-a-library-or-gem.md)
- [How to build for another target](how-to/build-for-another-target.md)
- [How to run the tests](how-to/run-the-tests.md)
- [How to add a spec](how-to/add-a-spec.md)
- [How to debug a wrong answer](how-to/debug-a-wrong-answer.md)
- [How to add a method to the core library](how-to/add-a-core-method.md)
- [How to port a C extension](how-to/port-a-c-extension.md)
- [How to check a gem](how-to/check-a-gem.md): which gems zr compiles,
  and what stops the others
- [How to update the vendored code](how-to/update-vendored-code.md)
- [How to test on another target](how-to/test-on-another-target.md)
- [How to measure performance](how-to/measure-performance.md)
- [How to release zr](how-to/release.md)

## Reference: find a fact

Facts about commands, formats and layouts.

- [What zr supports](reference/support.md): the syntax and the
  libraries that zr refuses, and what each target may fail
- [The `zr` command](reference/cli.md)
- [Tools](reference/tools.md): `bin/setup`, `bin/test`, `bin/console`,
  the rake tasks and the `zr-dev` commands
- [Environment variables](reference/environment-variables.md)
- [Targets](reference/targets.md)
- [Differences from ruby](reference/differences-from-ruby.md): what zr
  refuses on purpose, and the ruby bugs that zr does not copy
- [Dependencies](reference/dependencies.md)
- [Gem compatibility](reference/gem-compat.md): how far each gem that
  `zr-dev gems` tried gets with zr
- [The spec DSL](reference/spec-dsl.md): `zr`, `must_answer` and the
  format rules of a spec file
- [Whole programs](reference/test-format.md): the e2e programs and
  their recordings
- [Repository layout](reference/repository-layout.md)
- [The machine dialect](reference/machine-dialect.md)
- [Runtime layouts](reference/runtime-layouts.md)
- [Glossary](reference/glossary.md)

## Explanation: understand the design

Why zr is as it is.

- [Questions and answers](explanation/faq.md): the ruby version, gems,
  binary size, speed, build time, hosts and licenses
- [zr and other Rubies](explanation/zr-and-other-rubies.md): CRuby,
  ruby.wasm, TruffleRuby, JRuby, mruby, Natalie and Spinel
- [The contract: ruby's output or a refusal](explanation/the-contract.md)
- [Performance](explanation/performance.md): run time against ruby and
  YJIT, build time, and the known slow paths
- [Architecture](explanation/architecture.md)
- [The runtime](explanation/the-runtime.md)
- [Memory and the collector](explanation/memory-and-the-collector.md)
- [Method dispatch and unwinding](explanation/method-dispatch-and-unwinding.md)
- [Threads, fibers and ractors](explanation/threads-fibers-and-ractors.md)
- [Eval in a compiled program](explanation/eval-in-a-compiled-program.md)
- [How the tests run](explanation/how-the-tests-run.md)
- [Bootstrapping](explanation/bootstrapping.md)
- [Why zr has no C](explanation/why-zr-has-no-c.md)
- [How zr's Ruby is written](explanation/ruby-style.md)
