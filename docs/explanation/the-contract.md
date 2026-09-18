# The contract: ruby's answer or a refusal

ze0 makes one promise. A program that ze0 compiles answers exactly what
ruby 4.0.6 answers: the same stdout, the same stderr, and the same exit
status. When ze0 cannot keep that promise for a program, it does not
compile the program. It names the form it cannot compile, gives the
line, and exits with status 3.

This page explains why the promise has this shape, and how the project
keeps it.

## Why "exactly"

A compiler for a subset of Ruby could answer "close enough". Many
Ruby-to-native projects do. The cost of that falls on the person who
runs the program: a hash that iterates in another order, a float that
prints with one digit more, or an error message with other words can
break a program in ways that are hard to find.

So ze0 treats every observable difference as a bug: the order of hash
keys, `Float#to_s`, the text of an `ArgumentError`, the rows of a
backtrace, `nil.object_id`, the order of a tied `sort`. That is why the
runtime copies CRuby's value tagging, ports CRuby's `ruby_qsort`, and
ports Onigmo and prism rather than writing new engines.

## Why a refusal is better than a guess

A form that ze0 compiles wrongly is worse than a form it does not
compile. A wrong answer can pass tests and reach production. A refusal
stops at build time, at the line, with a name. So the compiler has no
"best effort" paths: a form it cannot lower is refused, and a runtime
feature that is not there stops the program by name.

## Why ruby is the only oracle

A test needs a right answer to compare with. ze0 takes that answer from
one place: ruby 4.0.6, the version in `.ruby-version`. It never compares
with another implementation, and a person never writes an expected
answer by hand.

Every literal a spec asserts was written by ruby and lifted from a
recording ruby made, and `rake oracle` re-asks ruby for each one. The
whole programs in `test/e2e/` and `test/bench/` carry ruby's answer
in the files beside it, written by `rake record`. A recording is made once. If
the right answer changes, the program has changed, so it is a new
program.

The ports follow the same rule. `tools/prism_diff.rb`,
`tools/regexp_diff.rb` and `tools/zlib_diff.rb` compare the Ruby ports
with ruby's own C on the host, case by case.

## How the specs keep the promise

`test/spec/` holds thousands of small programs, grouped by area:
`lang/` for the language, `core/` for core classes, `stdlib/` for
libraries, `compiler/` for what ze0 does with them. `rake test:spec`
compiles each one, runs what it built, and holds all four parts of the
answer -- stdout, stderr, the signal and the exit status -- to what
ruby said. A program ze0 refuses, or cannot build, **skips** and is
counted; only a wrong answer, a crash or a timeout fails.

An example ze0 does not answer yet says so where it sits, with
`skip "<what it waits on>"`. Every other example passes, so a new
failure is always news, and a gap is a line to delete rather than a file
to move back.

## More than the answers

The specs test answers. The units test the parts that make the
answers:

- `IR::Interp` runs IR without the backend. When the binary and the
  interpreter disagree, the backend has the bug.
- The disassembly snapshot pins the instructions the backend picks for
  each IR operation, so a change arrives as a diff to read.
- `ZR_GC_STRESS=1` collects at every allocation, so a value the
  collector does not see fails at once instead of rarely.
- `ZR_MCACHE=verify` checks every method cache hit against a fresh
  lookup.
- `rake stage1` and `rake stage2` compile the compiler with itself and
  compare bytes. See [Bootstrapping](bootstrapping.md).
