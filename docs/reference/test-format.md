# The program format

Two suites hold whole programs rather than examples: `test/e2e/`, built
through a real link and run as binaries, and `test/bench/`, timed. In
both, one `.rb` file is one program. The program is the file, and the
answer is recorded under `__END__` at the bottom of it. Ruby stops
lexing at `__END__`, so the recording costs the program nothing and can
hold any bytes — binary output, invalid UTF-8 — without escaping.

Most of what ze0 is held to is not written this way. A language
question is a spec example, which inlines its program and is compiled
in process; see [Add a spec](../how-to/add-a-spec.md). A program earns
a place here when the question is about the product rather than the
language: that `ze0 build` writes a binary, and that the binary starts,
reads its ARGV, opens a socket, takes a signal and flushes its output
at exit.

`rake 'record[<path>]'` writes the trailer, from the answer of the ruby
the `.ruby-version` pins. A trailer is never written by hand, and the
tool refuses a program that carries one already: a change of answer is
a change of program. `ruby tools/record.rb --os linux <path>...`, run
on that platform's ruby, writes the platform's sections instead: the
ones where its answer parts from macOS's, in place of the ones it wrote
before. `--ruby "<command>"` names the oracle when `ruby` is not it
(ruby.wasm under wasmtime for `--os wasi`).

```ruby
#@ args: --seed 42
puts "ab".upcase
$stderr.puts "warn"
exit 3
__END__
AB
#@ stderr
warn
#@ exit 3
```

## Header directives

A directive is a line starting `#@` at column 0, anywhere above
`__END__`, in any order. An unknown key fails the program rather than
being ignored.

| Directive | Meaning |
|---|---|
| `#@ args: <words>` | ARGV, shell-split, for both engines |
| `#@ stdin: <path>` | bytes piped to both engines; the path is relative to the program's own directory |
| `#@ env: K=V ...` | environment for both engines |
| `#@ ruby: <flags>` | flags for the oracle only |
| `#@ zeo-env: K=V ...` | environment for the compiled program only |
| `#@ only: <platforms>` | skip on every platform the list does not name: `macos`, `linux`, `wasi`, separated by commas or spaces |
| `#@ needs: libssl` | skip where the library is absent: libssl 3 in `OPENSSL_DIR` or the Homebrew and MacPorts prefixes, on macOS only |
| `#@ build-mb: <megabytes>` | the build's memory bound, for a program known to need more than `ZE0_BUILD_MB` |
| `#@ skip: <why>` | ze0 does not answer this one yet, and this is what it waits on |

## The trailer

Everything after a line that is exactly `__END__`.

The stdout body starts on the next line and runs to the next marker or
to the end of the file. A marker is a line at column 0 that is exactly
one of:

| Marker | Meaning |
|---|---|
| `#@ stderr` | what follows is stderr |
| `#@ exit N` | the exit status |
| `#@ signal N` | the signal that killed it |
| `#@ nonl` | the body before this has no trailing newline |
| `#@ linux stdout` / `#@ linux stderr` / `#@ linux exit N` / `#@ linux signal N` | where the answer on linux parts from macOS's; `wasi` takes the same forms |

The unprefixed sections are macOS's. A platform's answer is each
section it recorded, and macOS's for the rest: a program whose linux
run differs only in stdout carries only `#@ linux stdout`. `#@ nonl`
ends whichever section it follows.

`#@ exit` is omitted when the status is 0. `#@ stderr` is omitted when
stderr is empty, and its absence means stderr **must** be empty.

A body line that would look like a marker is escaped: the writer
prefixes `#` to any line matching `^#+@`, and the reader strips one `#`
from any line matching `^##+@`. So any output round-trips.

## Two rules

- A program may not reference `DATA`. Ruby would hand it the trailer.
- A program may not read `__FILE__` as a file, for the same reason.

`rake test:unit N=/CaseFormat/` holds both.

## Where a program goes

| Directory | What lives there |
|---|---|
| `test/e2e/<suite>/<area>/` | whole programs through a real link, filed by area as the specs are |
| `test/bench/` | the benchmark bank's inputs |

`test/e2e/` mirrors `test/spec/`, so `test/e2e/core/process` and
`test/spec/core/process` are about the same thing at two different
costs. A directory named `<name>/` beside `<name>.rb` holds that
program's own files.

`rake test:e2e` builds and runs them all, four builds at once.
`ruby -Ilib -Itest test/e2e/binaries_test.rb -n /socket/` runs one.

One trap worth naming: minitest filters its own frames out of a
backtrace with `%r%lib/minitest%`, and `stdlib/minitest` matches it. A
program on that path filters its own frames out too, the filter falls
through to the whole backtrace, and ruby's answer becomes absolute
paths into whoever's gem store recorded it. The two suite-runner
programs live in `test/e2e/stdlib/testing/` for that reason.

## Other targets

`rake test:e2e TARGET=<triple>` builds every program for that target
and runs it where the target runs: a native binary on its own host, a
wasm module under `wasmtime run --dir .` with the `#@ env:` pairs
passed as `--env`. The answer it is held to is that platform's
(`macos`, `linux` or `wasi`), section by section as above, and a wasm
trap counts as a crash. `rake test:spec TARGET=<triple>` does the same
for the spec road.

A target on its way in is held to what it did, not to the whole tier.
`test/baselines/<triple>.txt` names the programs it is allowed to fail,
one `<path>` and reason a line, separated by a tab:

```
e2e/stdlib/openssl/openssl_digest.rb	the wasi layer has no dlopen
```

A named program that fails is skipped with its reason. A named program
that **passes** fails the run and says to take it off the file, so the
baseline can never go stale.
