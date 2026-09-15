# Test format

One `.rb` file is one test. The program is the file, and the answer is
recorded under `__END__` at the bottom of it. Ruby stops lexing at `__END__`,
so the recording costs the program nothing and can hold any bytes — binary
output, invalid UTF-8 — without escaping.

`ruby tools/record.rb <case path>...` writes the trailer, from the answer of
the ruby the `.ruby-version` pins. A trailer is never written by hand, and the
tool refuses a case that carries one already: a change of answer is a change
of program. `ruby tools/record.rb --os linux <case path>...`, run on that
platform's ruby, writes the platform's sections instead: the ones where its
answer parts from macOS's, in place of the ones it wrote before. `--ruby
"<command>"` names the oracle when `ruby` is not it (ruby.wasm under wasmtime
for `--os wasi`).

`ruby tools/test.rb <case path>...` runs one program the way `ze0 test` runs
it and shows the whole of it: the build and its time, what the binary
answered, and every line where that answer parts from the recording. `ze0
test` stays the gate over many programs; this is the bench beside it.

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

A directive is a line starting `#@` at column 0, anywhere above `__END__`,
in any order. An unknown key fails the case rather than being ignored.

| Directive | Meaning |
|---|---|
| `#@ args: <words>` | ARGV, shell-split, for both engines |
| `#@ stdin: <path>` | bytes piped to both engines; the path is relative to the program's own directory |
| `#@ env: K=V ...` | environment for both engines |
| `#@ ruby: <flags>` | flags for the oracle only |
| `#@ zeo: <flags>` | flags for the compiled program's CLI only (kept from the recordings) |
| `#@ zeo-env: K=V ...` | environment for the zeo child only |
| `#@ only: <platforms>` | skip on every platform the list does not name: `macos`, `linux`, `wasi`, separated by commas or spaces |
| `#@ backend: jit` | skip wherever a real link is used; the program needs the compiler and itself in one process |
| `#@ gccheck: <line>` | the exit cycle census this program is expected to report |

## The trailer

Everything after a line that is exactly `__END__`.

The stdout body starts on the next line and runs to the next marker or to the
end of the file. A marker is a line at column 0 that is exactly one of:

| Marker | Meaning |
|---|---|
| `#@ stderr` | what follows is stderr |
| `#@ exit N` | the exit status |
| `#@ signal N` | the signal that killed it |
| `#@ nonl` | the body before this has no trailing newline |
| `#@ linux stdout` / `#@ linux stderr` / `#@ linux exit N` / `#@ linux signal N` | where the answer on linux parts from macOS's; `wasi` takes the same forms |

The unprefixed sections are macOS's. A platform's answer is each section it
recorded, and macOS's for the rest: a case whose linux run differs only in
stdout carries only `#@ linux stdout`. `#@ nonl` ends whichever section it
follows.

`#@ exit` is omitted when the status is 0. `#@ stderr` is omitted when stderr
is empty, and its absence means stderr **must** be empty.

A body line that would look like a marker is escaped: the writer prefixes `#`
to any line matching `^#+@`, and the reader strips one `#` from any line
matching `^##+@`. So any output round-trips.

## Two rules the corpus enforces

- A program may not reference `DATA`. Ruby would hand it the trailer.
- A program may not read `__FILE__` as a file, for the same reason.

`ze0 check` holds both.

## Where a program goes

| Directory | What lives there | Who recorded the trailer |
|---|---|---|
| `test/lang/<area>/` | language semantics | ruby |
| `test/core/<class>/` | core classes | ruby |
| `test/stdlib/<lib>/` | bundled libraries | ruby |
| `test/compiler/<area>/` | compiler-specific behaviour | ruby |
| `test/aot/` | programs that also run through a real link | ruby |
| `test/milestones/` | whole require graphs | ruby |
| `test/ze0/` | the programs ze0's own subset is held to | ruby |
| `test/bench/` | the benchmark bank's inputs | ruby |
| `test/gaps/` | programs ze0 does not get right yet; ordinary here | ruby |

The four topic roots are exactly two levels deep: `<topic>/<area>/<name>.rb`.
Anything deeper is a fixture, not a case. A directory named `<name>/` beside
`<name>.rb` holds that program's own files, and a `fixtures/` directory holds
shared ones.

A case is named `<suite>::<path>` -- `core::string/upcase.rb` -- which is the
spelling every `ze0 test` filter takes.

## Other targets

`ze0 test --target <triple>` builds every program for that target and runs
it where the target runs: a native binary on its own host, a wasm module
under `wasmtime run --dir .` with the `#@ env:` pairs passed as `--env`.
The answer it is held to is the target's platform's (`macos`, `linux` or
`wasi`), section by section as above, and a wasm trap counts as a crash.

A target on its way in is held to what it did, not to macOS's whole corpus:
`--baseline test/baselines/<triple>.txt` passes when every defect row is
one the baseline names. A baseline is a sweep's own `tmp/sweep.txt`, and
the rows that joined or left the defects are named. Without the file the
rows are reported, not required.
