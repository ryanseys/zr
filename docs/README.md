# ze0 documentation

The documentation has four parts. Each part answers a different need.

## Tutorials: start here

Lessons that take you from nothing to a result, one step at a time.

- [Compile your first program](tutorials/compile-your-first-program.md):
  install ze0, and build one Ruby file as a binary and as a WebAssembly
  module.
- [Add your first spec](tutorials/add-your-first-spec.md): work in a
  checkout, ask ruby for the answer, and see ze0 match it.

## How-to guides: get a task done

Steps for a goal you already have.

- [How to build for another target](how-to/build-for-another-target.md)
- [How to add a spec](how-to/add-a-spec.md)
- [How to run the checks](how-to/run-the-checks.md)
- [How to debug a program that diverges](how-to/debug-a-program-that-diverges.md)
- [How to add a method to the core library](how-to/add-a-core-method.md)
- [How to port a C extension](how-to/port-a-c-extension.md)
- [How to change the version of a library ze0 carries](how-to/bump-a-library.md)
- [How to hold another target](how-to/hold-another-target.md)
- [How to measure performance](how-to/measure-performance.md)

## Reference: look it up

Facts about commands, formats and layouts.

- [Command line](reference/cli.md): `ze0` and the rake tasks
- [Environment variables](reference/environment-variables.md)
- [Targets](reference/targets.md)
- [Differences from ruby](reference/differences-from-ruby.md): what ze0 refuses on purpose, and the ruby bugs it does not copy
- [Dependencies](reference/dependencies.md)
- [Whole programs](reference/test-format.md)
- [Tools](reference/tools.md)
- [Repository layout](reference/repository-layout.md)
- [The kernel dialect](reference/kernel-dialect.md)
- [Runtime layouts](reference/runtime-layouts.md)
- [Glossary](reference/glossary.md)

## Explanation: understand the design

Why ze0 is built the way it is.

- [The contract: ruby's answer or a refusal](explanation/the-contract.md)
- [Architecture](explanation/architecture.md)
- [The runtime](explanation/the-runtime.md)
- [Memory and the collector](explanation/memory-and-the-collector.md)
- [Method dispatch and signals](explanation/method-dispatch-and-signals.md)
- [Threads, fibers and ractors](explanation/threads-fibers-and-ractors.md)
- [Eval in a compiled program](explanation/eval-in-a-compiled-program.md)
- [Bootstrapping](explanation/bootstrapping.md)
- [Why ze0 has no C](explanation/why-ze0-has-no-c.md)
