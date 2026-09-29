# How to update zr's standard library

This guide shows you how to write `stdlib/` again: zr's copy of ruby
4.0.7's pure-Ruby standard library. A program's `require` of a default
or bundled gem, such as `csv` or `uri`, reads these files. zr never
reads the host's gems, so a change to the library is always a change
to `stdlib/`.

`stdlib/` is a stock ruby's library, byte for byte, laid out as a ruby
install lays it out:

| Path | What |
|---|---|
| `stdlib/lib/ruby/4.0.0/` | ruby's own library, the default gems, rubygems and bundler |
| `stdlib/lib/ruby/gems/4.0.0/gems/<name>-<version>/` | each bundled gem's `lib` and license files |
| `stdlib/lib/ruby/gems/4.0.0/specifications/` | the gemspec of each gem |
| `stdlib/LICENSES/` | the license texts of the default gems and of ruby |
| `stdlib/CHECKSUMS` | the SHA-256 of each bundled `.gem` file |
| `lib/zr/stdlib.rb` | the name and version of each gem (`Zr::Stdlib`) |

Do not edit these files by hand. `zr-dev gen stdlib` writes them all.

A gem with a C part is different: zr owns its port, at a version that
`lib/zr/ports.rb` gives. See
[How to port a C extension](port-a-c-extension.md).

## 1. Write the tree again

```console
$ ruby tool/zr-dev.rb gen stdlib
```

The generator reads:

- ruby's own library and the default gems from the running ruby's
  `rubylibdir`. Run it on a stock ruby 4.0.7 (`.ruby-version`); the
  generator stops on another ruby.
- the version of each bundled gem from CRuby's `gems/bundled_gems` at
  `RUBY_REVISION` (`RUBY_SRC`, see [Tools](../reference/tools.md)).
- each bundled `.gem` from rubygems.org, into `tmp/stdlib/cache`. The
  generator stops when a file's SHA-256 is not the one in
  `stdlib/CHECKSUMS`. It adds the line for a gem that is not there yet,
  with the SHA-256 that rubygems.org gives.

It removes the files that a gem no longer has.

## 2. Check the tree

```console
$ ruby tool/zr-dev.rb gen stdlib --check
```

It fails when a file differs from what the generator writes. CI runs
this check in the Alpine container against the CRuby source.

## 3. Install the test reference again

```console
$ ruby tool/zr-dev.rb reference
```

The expected output of each spec comes from ruby with the same gem
versions as `stdlib/`, in `tmp/reference/gems`. `bin/setup` also runs
this step.

## 4. Run the tests that the change reaches

```console
$ ruby tool/zr-dev.rb affected
```

Run the specs that it lists, one directory at a time. If ruby gives a
different output with the new version, get the new output from ruby,
as [How to add a spec](add-a-spec.md) shows.

## A new ruby

A new ruby release (for example a patch release with a security fix in
a default gem) is a new toolchain. Change `.ruby-version`, `Zr::RUBY`
and `RUBY_REVISION`, install that ruby, then do steps 1 to 4. zr's
standard library follows ruby's releases: to get a fixed gem, release
zr for the ruby release that includes it. See also
[ruby 4.0.7 is part of the toolchain](../explanation/the-contract.md#ruby-407-is-part-of-the-toolchain).
