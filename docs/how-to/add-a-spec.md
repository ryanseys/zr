# How to add a spec

A spec holds ze0 to ruby for one program. The program is written inline,
ze0 compiles it, the binary runs, and what it said is what the example
asserts.

## Write one

Specs live in `test/spec/<suite>/<area>/<subject>_test.rb`. Find the
file whose subject your program is about — `core/string/frozen_test.rb`,
`lang/blocks/enumeration_test.rb` — and add an example to it:

```ruby
it "keeps the receiver's encoding" do
  _(ze0(<<~'RUBY')).must_answer "UTF-8\n"
    puts "ab".upcase.encoding
  RUBY
end
```

`must_answer` holds the whole answer, not a part of it: stderr must be
empty and the status zero unless you say otherwise. That is what the
oracle means — a program that also wrote a backtrace has not matched.

When there is more to say, name the result and let the output read as
output:

```ruby
it "writes the message to stderr and exits 1" do
  result = ze0(<<~'RUBY')
    puts "out"
    abort "stopping here"
  RUBY

  _(result).must_answer <<~'OUT', stderr: "stopping here\n", status: 1
    out
  OUT
end
```

## What `ze0` takes

| Keyword | For |
|---|---|
| `argv:` | the program's `ARGV` |
| `env:` | the environment it runs under |
| `stdin:` | the bytes piped to it |
| `files:` | the program's own files, keyed by the name it reaches for them by |
| `path:` | the name the program answers to, when its own output carries it |

`path:` matters only for a program whose answer names its source — a
backtrace, or `__FILE__` — **and** wants a name other than the default.
The default is the spec file's own path under `test/spec`: an example in
`test/spec/core/fiber/fiber_test.rb` writes its program as
`core/fiber/fiber_test.rb`, so a backtrace names the file the example is
written in (`Ze0::Reader.path_for`).

It used to be the example's sentence, slugified, which is why no
description in this suite holds an apostrophe, a comma or a `#` — a
sentence had to survive being turned into a filename. It does not any
more, so write the sentence you mean, and know that renaming an example
cannot move the program it introduces.

Spell `path:` out when the program is *about* its own path — the
`ze0/...` examples, a program given an absolute name, one that asks what
`/` or `/a b/c` expands to.

The `_test` in the derived name stays on purpose. `core/fiber/fiber.rb`
reads better but collides: `stdlib/etc/etc_test.rb` hands its programs an
`etc.rb` of their own, `files:` is written after the program, and the
fixture would land on top of it — the example would then run the fixture
and answer something that looks like an answer. That collision is refused
now rather than silently taken.

Two things about those keywords are easy to get wrong:

- A `files:` key is resolved against the directory the **program** sits in,
  but a filename in `argv:` is resolved against the directory the program
  **runs in**. When `path:` names a subdirectory the two differ, and the
  same file needs two spellings — see `core/io/io_test.rb`, where
  `files: {"argf_input.txt" => …}` is reached as
  `argv: ["core/io/argf_input.txt"]`.
- A `files:` value is bytes, not a filename. `{ symlink: "lib" }` in place
  of the bytes makes a link instead, for a program that asks whether two
  paths reach one file.

## How an example is written

One example is one behaviour. The call and the assertion are already
separated everywhere in the suite — name the result, leave a blank line,
then assert:

```ruby
it "keeps the receiver's encoding" do
  result = ze0(<<~'RUBY')
    # one sentence saying what this pins

    s = "ab"
    out = s.upcase
    puts out.encoding
  RUBY

  _(result).must_answer "UTF-8\n"
end
```

Assemble, act and assert cannot live in the spec file, because the program
*is* the thing under test. So they live inside the heredoc, in that order,
and the program prints exactly what the claim is about. A program that
prints many rows should label them — `puts "#{name}\t#{value}"` — so a
failure names the row that moved instead of showing a wall of output.

Write the sentence for a reader who has not seen the program: present
tense, no trailing period, and no repetition of what the `describe`
already said. `describe "Hash: comparison and equality"` plus
`it "hash equality ignores order"` says "hash" twice; the example is
`it "ignores insertion order"`.

Say what the program shows, not what it is about. A tracker number
(`it "issue 3016"`) names something the reader does not have; a noun
phrase (`it "range one sided search"`) names a subject and leaves the
claim out. The sentence a reader wants is the claim: "Math.lgamma is
exactly [Infinity, 1] at every non-positive integer pole", "find, detect
and take_while over an endless range stop at their answer".

Two examples may not share a sentence, in one file or across two —
`spec:check` refuses it, because a failure report that names a sentence,
or a `-n` filter written from one, has to name one example. The single
exception is a sentence a generator writes into one file per subject;
`SpecStyle::GENERATED` lists it and says which generator.

Two examples may not share a *program* either. When the same program
answers a question in two areas, the area whose behaviour it is evidence
for keeps it and the other drops it — `rake spec:check` does not catch
this one, so read what the program demonstrates rather than which file
it sits in.

The `describe` names the subject and, in a file that is not the
subject's own, the facet: `describe "Hash programs"` in
`core/hash/hash_test.rb`, `describe "Hash: comparison and equality"` in
`core/hash/comparison_test.rb`. Spell a library the way ruby does —
`BigDecimal`, `CGI`, `FileUtils` — not the way its directory does.

## Keep the file in shape

```console
$ rake 'spec:check[test/spec/core/string]'   # line length, heredoc tags, trailing space
```

Scoped to a path, it compares sentences only within that path. Run it
bare over the whole suite before you push a batch of renames, or a
sentence you wrote can collide with one in an area you were not looking
at.

A program is `<<~'RUBY'` and an answer is `<<~'OUT'`, both with the tag
quoted — an unquoted tag makes `#{}` inside a Ruby program interpolate
before ze0 ever sees it. Use `<<~'PROGRAM'` for a program that opens a
`RUBY` heredoc of its own, since a `<<~` terminator may be indented and
the inner one would otherwise end the outer.

## Run it

```console
$ bundle exec minitest test/spec/core/string/frozen_test.rb
$ ruby -Ilib -Itest test/spec/core/string/frozen_test.rb -n "/encoding/"
$ bundle exec minitest test/spec/core/string
```

## Where the answer comes from

Never from you. Every literal in `test/spec/` was written by ruby 4.0.6
and lifted from the recording it wrote. If you are adding a program ze0
does not answer yet, write what **ruby** says, and check it:

```console
$ ruby -e 'puts "ab".upcase.encoding'
UTF-8
```

## What ze0 will not compile

An example whose program uses a form outside ze0's subset **skips**,
naming the form, and joins the refusal census at the end of the run.
That is the roadmap, not a failure. A program that diverges, crashes or
runs past its limit fails.

## Hold the literal to ruby again

`rake oracle` runs each example's program under the ruby the
`.ruby-version` pins and holds the example to what it said, compiling
nothing. It is how a hand-written literal earns the same standing as a
lifted one:

```console
$ rake 'oracle[test/spec/core/string/frozen_test.rb]'
```

## A whole program, end to end

A program that needs a real link or a whole require graph is not a
spec. Those live in `test/e2e/<suite>/<area>/` as programs with ruby's
answer in the files beside it; see
[Whole programs](../reference/test-format.md).
