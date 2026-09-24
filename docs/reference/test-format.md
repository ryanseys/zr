# Whole programs

Two suites hold whole programs rather than examples: `test/e2e/`, built
through a real link and run as binaries, and `benchmark/`, timed.

A program is a `.rb` file and nothing else — no header, no trailer,
nothing to parse. `ruby test/e2e/core/process/signal_trap.rb` runs it,
and that is the point: the program you debug is the program the tier
builds.

What ruby answered sits beside it, in files that hold those bytes and
no others:

```
test/e2e/core/process/
  exit_status.rb        the program
  exit_status.out       what it wrote to stdout
  exit_status.err       what it wrote to stderr, when it wrote any
  exit_status.status    the exit status, when it was not 0
  exit_status.signal    the signal that ended it, if one did
```

Nothing is escaped and nothing has a marker, so a program may write any
bytes at all — binary output, invalid UTF-8, a last line with no
newline — and a wrong answer is a `diff` of two files.

Most of what zr is held to is not written this way. A language
question is a spec example, which inlines its program and is compiled
in process; see [Add a spec](../how-to/add-a-spec.md). A program earns
a place here when the question is about the product rather than the
language: that `zr build` writes a binary, and that the binary starts,
reads its ARGV, opens a socket, takes a signal and flushes its output
at exit.

## Recording

`rake 'record[<path>]'` runs the program under the ruby the
`.ruby-version` pins and writes the files above. ruby 4.0.6 is the only
source of right answers, so nothing else writes them and none of them
is written by hand. A program that is already recorded is left alone;
`rake 'record[--again <path>]'` is how you say you mean to
replace an answer, and a change of answer should be a change of
program.

## What a program needs

Nearly every program is built and run with no arguments, no environment
of its own and no conditions. The few that need something are named in
`Zr::E2E::HOW`, in `test/support/e2e.rb`:

```ruby
HOW = {
  "core/process/argv_and_env" => { argv: %w[alpha beta], env: { "ZR_TEST_AOT_SMOKE" => "on" } },
  "stdlib/bundler/require_bundler" => { build_mb: 3072 },
  "stdlib/openssl/openssl_digest" => { needs: ["libssl"] }
}.freeze
```

| Key | Means |
|---|---|
| `argv:` | what the binary is started with |
| `env:` | what it is started under |
| `stdin:` | a file beside the program, fed to it |
| `needs:` | what this machine must have, or the program skips |
| `only:` | the platforms that run it |
| `build_mb:` | a memory bound for the build, above the usual one |
| `skip:` | why it does not run at all, in words |

`rake record` reads the same table, so a program is asked of ruby the
way it is asked of zr.

## Another target

A target on its way in is held to what it did rather than to the whole
tier: `test/baselines/<triple>.txt` names the programs it is allowed to
fail and why, one path and reason a line, separated by a tab. A named
program that now passes fails the run, so the file cannot go stale.
