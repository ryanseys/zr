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
backtrace, or `__FILE__`. Everything else takes the default.

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
answer under `__END__`; see
[The program format](../reference/test-format.md).
