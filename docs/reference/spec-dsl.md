# The spec DSL

A spec file is a minitest spec file under
`test/spec/<suite>/<area>/<subject>_test.rb`. It requires
`spec_helper`, which adds two methods: `zr` in an example, and
`must_answer` on an expectation. `test/support/spec.rb` defines both.

```ruby
require "spec_helper"

describe "String: case mapping" do
  it "keeps the receiver's encoding" do
    result = zr(<<~'RUBY')
      puts "ab".upcase.encoding
    RUBY

    _(result).must_answer "UTF-8\n"
  end
end
```

For the steps to add an example, see
[How to add a spec](../how-to/add-a-spec.md).

## `zr(source, **keywords)`

Compiles `source` with zr, runs the binary, and returns a result with
`stdout`, `stderr`, `status` and `signal`. If zr refuses the program,
or the build makes no binary, the example skips. The skip message
gives the reason. If the program runs past its time limit, the example
fails.

| Keyword | Default | Value |
|---|---|---|
| `argv:` | `[]` | The program's `ARGV`. |
| `env:` | `{}` | Environment variables for the program. |
| `stdin:` | `nil` | The bytes that go to the program's stdin. |
| `files:` | `{}` | The program's own files: a Hash from a path to its bytes. `{ symlink: "<target>" }` in place of the bytes makes a symbolic link. |
| `path:` | the spec file's path below `test/spec` | The path of the program, relative to the directory it runs in. Backtraces and `__FILE__` show it. |
| `seconds:` | 60 (`ZR_TEST_SECONDS`) | The time limit for the run. |
| `ruby:` | `[]` | Command-line options for ruby only. `zr-dev oracle` and `zr-dev spec ask` use them to run the program under ruby. zr ignores them. |

### `path:`

The default path is the path of the spec file below `test/spec`. For
example, an example in `test/spec/core/fiber/fiber_test.rb` compiles
its program as `core/fiber/fiber_test.rb` (`Zr::Reader.path_for`). Thus
a backtrace gives the file that contains the example, and a change to
the sentence does not change the program.

Give `path:` only when the output of the program contains its own path
and the program needs a different path. Examples: a program that
prints its absolute path, or a program that asks what `/` or `/a b/c`
expands to.

The `_test` in the default path prevents a collision. Without it,
`stdlib/etc/etc_test.rb` would compile its programs as `etc.rb`, and a
`files:` entry named `etc.rb` would replace the program. zr refuses
such a collision.

### `files:` and `argv:`

A `files:` key is relative to the directory of the **program**. A file
name in `argv:` is relative to the directory where the program
**runs**. When `path:` has a subdirectory, the two are different, and
one file needs two spellings. For example, `core/io/io_test.rb` writes
`files: { "argf_input.txt" => ... }` and reads it with
`argv: ["core/io/argf_input.txt"]`.

### Fixtures

A large file or a large expected output goes in `test/fixtures/`, not
inline. These helpers read fixtures (`test/support/fixtures.rb`):

| Helper | Returns |
|---|---|
| `fixture("<name>")` | The bytes of `test/fixtures/<name>`. Use it for `files:` values or for an expected output. |
| `fixtures("<name>", ...)` | A `files:` Hash with each fixture at `../../fixtures/<name>`. |
| `beside("<name>", ...)` | A `files:` Hash with each fixture at `<name>`, beside the program. |

## `_(result).must_answer(stdout, **keywords)`

Checks all four parts of the result: stdout, stderr, the signal and the
exit status. A check of stdout alone would pass a program that also
wrote a backtrace.

| Keyword | Default | Value |
|---|---|---|
| `stderr:` | `""` | The expected stderr. |
| `status:` | `0` | The expected exit status. `nil` expects no status, for a program that a signal stopped. |
| `signal:` | `nil` | The number of the signal that stopped the program. |
| `linux:` | `nil` | The expected stdout on `aarch64-linux-musl`, when it is different from macOS. |
| `wasi:` | `nil` | The expected stdout on `wasm32-wasi`, when it is different from macOS. |

A platform that the call does not give expects the macOS stdout.

```ruby
it "names the platform" do
  result = zr(%(puts RUBY_PLATFORM))

  _(result).must_answer "arm64-darwin24\n", linux: "aarch64-linux-musl\n", wasi: "wasm32-wasi\n"
end
```

## A guard

An example that needs something this machine may not have gives it to
`it`. The example skips when the machine does not have it:

```ruby
it "signs with a key", needs: "libssl" do
  # ...
end

it "reads a Mach-O header", only: "macos" do
  # ...
end
```

`needs:` names items from `Zr::Harness::Needs`, as the e2e `needs:` key
does. `only:` names platforms (`macos`, `linux`, `wasi`). Both take one
name or a list. The reader (`zr-dev oracle`, `zr-dev spec verify`) takes
each `needs:` as met and reads `only:` against the host.

## A gap

An example that zr cannot pass yet stays in its place, with a `skip`
that tells what it needs:

```ruby
it "converts through the carrier's own UTF-8" do
  skip "the carrier tables hold Unicode's code points"
  # ...
end
```

When zr can pass it, delete the `skip` line.

## Format rules

`zr-dev spec check <path>` checks these rules, and
`zr-dev spec tidy <path>` fixes the ones that it can fix safely.

- A line of the file's own code is 120 columns or fewer. Lines inside a
  heredoc do not count.
- No trailing whitespace, except in an expected output.
- A heredoc that the DSL opens uses `<<~` and a quoted tag. An unquoted
  tag lets `#{}` in the program run before zr sees it.
- The tags are `RUBY` for a program, `OUT` for stdout, `ERR` for
  stderr, and `LINUX` or `WASI` for a platform's stdout. `PROGRAM` is a
  program that contains its own `RUBY` heredoc.
- Two examples do not have the same sentence, in one file or in two
  files. The one exception is a sentence that a generator writes into
  one file for each subject (`SpecStyle::GENERATED` lists it).

These rules are for a person, and `zr-dev spec check` does not check them:

- One example tests one behavior.
- Two examples do not have the same program. When the same program
  shows behavior in two areas, keep it in the area whose behavior it
  shows.
- Put a blank line between the call and the assertion.
- Use a string for an expected output of one or two lines with no
  escapes. Use a heredoc for three lines or more, or for text with `"`,
  `\` or a trailing space.
- A program that prints many values labels each one
  (`puts "#{name}\t#{value}"`), so that a failure shows which value
  changed.
- The sentence is present tense, has no period at the end, and does
  not repeat the `describe`. It tells what the program shows, not only
  its subject.
- The `describe` gives the subject, and in a file that is not the
  subject's own, the part of it: `describe "Hash: comparison and
  equality"`. Spell a library as ruby does: `BigDecimal`, `CGI`,
  `FileUtils`.
