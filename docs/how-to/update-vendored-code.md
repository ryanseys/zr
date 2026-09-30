# How to update the vendored code

This guide shows you how to change `vendor/`: the code that other
people wrote, which zr compiles into a program. That code is ruby
4.0.7's own library, its bundled gems, and the gems whose C part zr
ports. A program's `require` of `csv`, `uri` or `json` reads these
files. zr never reads the host's gems, so a change to a program's
library is always a change to `vendor/`.

`vendor/` is upstream code, byte for byte. Nobody edits a file there.
One file says what it holds, and one command writes it:

| Path | What |
|---|---|
| `lib/zr/vendor.rb` | the input: the bundled gems that `vendor/` holds, and the files that it leaves out, each with its reason |
| `lib/zr/ports.rb` | the input: each gem whose C part zr ports, at zr's version |
| `lib/zr/version.rb` | the input: the ruby release (`RUBY`, `RUBY_REVISION`) |
| `vendor/ruby/lib/ruby/4.0.0/` | ruby's own library, the default gems, rubygems and bundler, from ruby's source |
| `vendor/ruby/lib/ruby/gems/4.0.0/gems/<name>-<version>/` | each bundled gem and each port gem: its `lib` and its license files, from its `.gem` |
| `vendor/ruby/lib/ruby/gems/4.0.0/specifications/` | the gemspec of each gem |
| `vendor/ruby/gem_prelude.rb` | ruby's `gem_prelude.rb` |
| `vendor/src/prism-1.9.0/` | prism's `config.yml` and templates, from its git tag, for `zr-dev gen prism` |
| `vendor/LICENSES/` | the license texts that no gem directory holds |
| `vendor/vendor.lock` | the output: each source, and the SHA-256 of each `.gem` and each file |
| `lib/zr/stdlib.rb` | the output: the name and version of each gem (`Zr::Stdlib`) |

`vendor/ruby` is a ruby install prefix, as a stock ruby 4.0.7 leaves
it after a `gem install` of the port gems. `GEM_PATH=vendor/ruby/lib/ruby/gems/4.0.0 gem list`
lists its gems.

## Change what the tree holds

Every change is the same three steps: edit an input, write the tree,
run the tests that the tool names.

### Update a gem or a port

1. See what is newer on rubygems.org:

   ```console
   $ ruby tool/zr-dev.rb vendor outdated
   ```

2. See what the update changes, and which of zr's files replace one of
   the changed files:

   ```console
   $ ruby tool/zr-dev.rb vendor diff bigdecimal 4.1.3
   ```

3. Change the version: a port's in `lib/zr/ports.rb`. A bundled gem
   takes ruby's version: see [A new ruby](#a-new-ruby). For a port,
   also check `compat:`, the versions whose C interface the port
   implements.
4. Write the tree, and the tests below.

### Add a port

Add one line to `Zr::Ports::ALL` (`lib/zr/ports.rb`), and the C half in
Ruby under `runtime/ext`. `gem: true` vendors the gem at its version.
See [How to port a C extension](port-a-c-extension.md).

### Leave a file out

Add it to `LEFT_OUT` (ruby's library) or `GEM_EXCLUDE` (a gem) in
`lib/zr/vendor.rb`, with the reason. A file that zr refuses (`mkmf`,
`prism/ffi`) must not be in the tree, so that its `require` stops with
zr's reason.

## Write the tree

```console
$ ruby tool/zr-dev.rb vendor
```

The tool reads:

- ruby's own library from ruby's source at `RUBY_REVISION` (`RUBY_SRC`,
  see [Tools](../reference/tools.md)), as ruby's installer lays it out.
  It does not read the host's `rubylibdir`: a ruby build can patch it.
- the default gems' specifications from the running ruby. Run the tool
  on a stock ruby 4.0.7 (`.ruby-version`); it stops on another ruby.
- each `.gem` from rubygems.org, into `tmp/vendor/cache`. It stops when
  a file's SHA-256 is not the one in `vendor/vendor.lock`. A gem that is
  not in the lock yet must have the SHA-256 that rubygems.org publishes.
- prism's templates from its git tag (`PRISM_SRC`).

It removes the files that a source no longer has. A second run changes
nothing.

## Check the tree

```console
$ ruby tool/zr-dev.rb vendor --check
```

It needs no network: each file must have the SHA-256 in the lock, and
the inputs must not have changed since the lock was written.
`test/unit/vendor_test.rb` does the same check. CI also writes the tree
again from the sources and fails on a difference.

## Replace an upstream file

Do not edit a file in `vendor/`. zr's own code comes first on the load
path (`runtime/ext`, then `runtime/lib`), so a file there with the same
path replaces the upstream file: an overlay. The first lines of an
overlay name the file that it replaces and that file's digest:

```ruby
# frozen_string_literal: true
# zr overlay: replaces date.rb of date 3.5.1 (sha256 6026af9d0963)
```

When an update changes the replaced file, `test/unit/vendor_test.rb`
fails until you read the new upstream file, check the overlay against
it, and put the new digest in the line.

## Then

1. Install the test reference again. The expected output of each spec
   comes from ruby with the same gem versions as `vendor/`, in
   `tmp/reference/gems`. `bin/setup` also runs this step.

   ```console
   $ ruby tool/zr-dev.rb reference
   ```

2. Run the tests that the change reaches, one directory at a time:

   ```console
   $ ruby tool/zr-dev.rb affected
   ```

   If ruby gives a different output with the new version, get the new
   output from ruby, as [How to add a spec](add-a-spec.md) shows.

## A new ruby

A new ruby release (for example a patch release with a security fix in
a default gem) is a new toolchain. Change `.ruby-version`, `Zr::RUBY`
and `RUBY_REVISION`, install that ruby, then write the tree. The
library's directory name follows the release (`Zr::Layout::API`: 4.0.0
for every 4.0.x), and the lock shows each file that changes. The
bundled gems take the versions in ruby's `gems/bundled_gems`. zr's
library follows ruby's releases: to get a fixed gem, release zr for
the ruby release that includes it. See also
[ruby 4.0.7 is part of the toolchain](../explanation/the-contract.md#ruby-407-is-part-of-the-toolchain).
