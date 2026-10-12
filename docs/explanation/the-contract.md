# The contract: ruby's output or a refusal

zr makes one promise. A program that zr compiles gives exactly the
output of ruby: the same stdout, the same stderr, and the same
exit status. When zr cannot keep that promise for a program, it does
not compile the program. It gives the form that it does not support
and the line, and exits with status 3.

This page explains why the promise has this form, and how the project
keeps it.

## Why "exactly"

A compiler for a subset of Ruby can give output that is "close
enough". Many Ruby-to-native projects do. The person who runs the
program pays for this: a hash that iterates in a different order, a
float that prints one more digit, or an error message with other words
can break a program in ways that are hard to find.

Thus zr treats every visible difference as a bug: the order of hash
keys, `Float#to_s`, the text of an `ArgumentError`, the lines of a
backtrace, `nil.object_id`, the order of a tied `sort`. For this
reason, the runtime copies CRuby's value tagging, ports CRuby's
`ruby_qsort`, and ports Onigmo and prism in place of new engines.

## Why a refusal is better than a guess

A form that zr compiles incorrectly is worse than a form that it does
not compile. A wrong output can pass tests and get to production. A
refusal stops the build, at the line, with the name of the form. Thus
the compiler has no "best effort" paths: zr refuses a form that it
cannot lower, and a runtime feature that is not available stops the
program with a message that gives the feature.

## Why ruby is the only reference

A test needs a correct result to compare with. zr gets that result
from one place: the ruby that `.ruby-version` names. It never
compares with a different implementation, and a person never writes an
expected output by hand.

Every expected file of a program test comes from ruby: `zr-dev expect`
writes it, and `zr-dev expect --check` checks each one against ruby
again. The benchmarks in `benchmark/` have ruby's output in their
recordings, which `zr-dev record` writes. zr records a benchmark one
time. If the correct output changes, the program has changed, so it is
a new program.

The ports obey the same rule. Each one has its own area in
`test/programs/stdlib/`, checked program by program against ruby's C:
`zlib`, `prism`, `openssl` and the others. prism and Onigmo are checked
two times: `test/unit/prism_test.rb` and `regexp_diff_test.rb` compare
the port with ruby's C on the host, object by object, over a committed
sample.

## The pinned ruby is part of the toolchain

zr targets the latest Ruby 4 release. `.ruby-version` pins the exact
release, and that ruby is more than the reference. Its pure-Ruby standard library
is what a program's `require` reads, and the generated tables
(`zr-dev gen`) come from it. zr carries that library itself, in
`vendor/ruby`, as JRuby and TruffleRuby carry theirs: a stock ruby's
files, byte for byte (`zr-dev vendor --check`). A build never reads
the host's gems, so a distributor's patched copy of a gem, or a newer
gem that `gem update` installed, does not change a program.

The host ruby only runs the compiler. `zr build` and `zr run` run on
ruby 4.0 or later (a ruby of another series than the pinned one gives a
warning), and refuse an older ruby with status 3. Each generator task
stops on a ruby other than the pinned one. A newer ruby is a new
toolchain:
`.ruby-version`, `vendor/`, the tables, the expected outputs and the
recordings all change to it together.

## How the program tests keep the promise

`test/programs/` contains thousands of small programs, in areas:
`lang/` for the language, `core/` for core classes, `stdlib/` for
libraries, `compiler/` for what zr does with them, and `cli/` for the
product (`zr build`, the link, the process). `rake test:programs`
builds each one, runs the result, and checks all parts of the output
(stdout, stderr, the exit status and the signal) against ruby's. A
wrong output fails. A program that zr refuses, or cannot build or run,
is an error.

A test that a target cannot pass yet is in the target's baseline,
`test/baselines/<triple>.txt`, with the reason. Every other test
passes, and a test in the baseline that passes fails the run. Thus a
new failure always means that something changed, and a fixed gap is
one line to delete. See [Program tests](../reference/program-tests.md).

## More than the outputs

The program tests test outputs. The unit tests test the parts that
make the outputs:

- `IR::Interp` runs IR without the backend. When the binary and the
  interpreter give different results, the backend has the bug.
- The disassembly snapshot records the instructions that the backend
  selects for each IR operation, so a change shows as a diff to read.
- `ZR_GC_STRESS=1` collects at every allocation, so a value that the
  collector does not find fails at once, not rarely.
- `ZR_MCACHE=verify` checks every inline cache hit against a fresh
  lookup.
- `zr-dev stage 1` and `zr-dev stage 2` compile the compiler with
  itself and compare bytes. See [Bootstrapping](bootstrapping.md).
