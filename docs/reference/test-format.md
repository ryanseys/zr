# Whole programs

Two directories contain whole programs, not spec examples:
`test/e2e/`, which the e2e tier builds through a real link and runs as
binaries, and `benchmark/`, which `zr-dev bench` times.

A program is a `.rb` file and nothing else: no header and no trailer.
`ruby test/e2e/core/process/signal_trap.rb` runs it. Thus the program
that you debug is the program that the tier builds.

The program's recording is beside it, in files that contain only
ruby's bytes:

```
test/e2e/core/process/
  exit_status.rb        the program
  exit_status.out       what it wrote to stdout
  exit_status.err       what it wrote to stderr, if it wrote something
  exit_status.status    the exit status, if it was not 0
  exit_status.signal    the number of the signal that stopped it, if one did
```

Nothing is escaped and nothing has a marker. Thus a program can write
any bytes (binary output, invalid UTF-8, a last line with no newline),
and a wrong output is a `diff` of two files.

Most tests are not whole programs. A question about the language is a
spec example, which has its program inline and is compiled in the test
process; see [How to add a spec](../how-to/add-a-spec.md). A whole
program is for a question about the product, not the language: that
`zr build` writes a binary, and that the binary starts, reads its
ARGV, opens a socket, receives a POSIX signal and flushes its output
at exit.

## Recording

`zr-dev record <path>` runs the program under ruby 4.0.7 and writes
the files above. ruby 4.0.7 is the only source of expected outputs, so
nothing else writes them, and nobody writes them by hand. The command does
not change a program that has a recording.
`zr-dev record --again <path>` writes the recording again. A change of
output is usually a change of program.

## What a program needs

Most programs are built and run with no arguments, no environment of
their own and no conditions. `Zr::E2E::HOW`, in `test/support/e2e.rb`,
lists the programs that need something:

```ruby
HOW = {
  "core/process/argv_and_env" => { argv: %w[alpha beta], env: { "ZR_TEST_AOT_SMOKE" => "on" } },
  "stdlib/bundler/require_bundler" => { build_mb: 3072 },
  ...
}.freeze
```

| Key | Value |
|---|---|
| `argv:` | the arguments of the binary |
| `env:` | the environment of the binary |
| `stdin:` | a file beside the program, which goes to its stdin |
| `needs:` | what the machine must have; if it does not, the program skips |
| `only:` | the platforms that run it |
| `build_mb:` | a memory limit for the build, above the default one |
| `run_mb:` | a memory limit for the run, above the default one |
| `skip:` | why it does not run, in words |

`zr-dev record` reads the same table, so ruby runs a program in the same
way as zr does.

## Another target

A target can be allowed to fail some programs. See
[How to test on another target](../how-to/test-on-another-target.md).
