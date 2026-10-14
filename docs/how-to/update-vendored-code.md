# How to update the vendored code

This guide shows you how to change `vendor/`: the code that other
people wrote, which zr compiles into a program. That code is the pinned
ruby's own library, its bundled gems, and the gems whose C part zr
ports. A program's `require` of `csv`, `uri` or `json` reads these
files. zr never reads the host's gems, so a change to a program's
library is always a change to `vendor/`.

`vendor/` is upstream code, byte for byte. Nobody edits a file there.
One file says what it holds, and one command writes it:

| Path | What |
|---|---|
| `tool/lib/zr/dev/vendored.rb` | the input: the bundled gems that `vendor/` holds, and the files that it leaves out, each with its reason |
| `lib/zr/library/ports.rb` | the input: each gem whose C part zr ports, at zr's version |
| `lib/zr/ruby_version.rb` | the input: the ruby release (`RUBY`, `RUBY_REVISION`), which `zr-dev gen ruby_version` writes from `.ruby-version` |
| `vendor/ruby/lib/ruby/<ruby_version>/` | ruby's own library, the default gems, rubygems and bundler, from ruby's source |
| `vendor/ruby/lib/ruby/gems/<ruby_version>/gems/<name>-<version>/` | each bundled gem and each port gem: its `lib` and its license files, from its `.gem` |
| `vendor/ruby/lib/ruby/gems/<ruby_version>/specifications/` | the gemspec of each gem |
| `vendor/ruby/gem_prelude.rb` | ruby's `gem_prelude.rb` |
| `vendor/src/prism-1.9.0/` | prism's `config.yml` and templates, from its git tag, for `zr-dev gen prism` |
| `vendor/LICENSES/` | the license texts that no gem directory holds |
| `vendor/vendor.lock` | the output: each source, and the SHA-256 of each `.gem` and each file |
| `lib/zr/library/stdlib.rb` | the output: the name and version of each gem (`Zr::Library::Stdlib`) |

`vendor/ruby` is a ruby install prefix, as a stock ruby of the pinned
version leaves it after a `gem install` of the port gems.
`<ruby_version>` is that ruby's library version (RbConfig's
`ruby_version`, `Zr::Library::Layout::API`).
`GEM_PATH=vendor/ruby/lib/ruby/gems/<ruby_version> gem list` lists its
gems.

## Change what the tree holds

Every change is the same three steps: edit an input, write the tree,
run the tests that the tool names.

### Update a gem or a port

1. See what is newer on rubygems.org:

   ```console
   $ bin/zr-dev vendor outdated
   ```

2. See what the update changes, and which of zr's files replace one of
   the changed files:

   ```console
   $ bin/zr-dev vendor diff bigdecimal 4.1.3
   ```

3. Change the version: a port's in `lib/zr/library/ports.rb`. A bundled gem
   takes ruby's version: see [A new ruby](#a-new-ruby). For a port,
   also check `compat:`, the versions whose C interface the port
   implements.
4. Write the tree, and the tests below.

### Add a port

Add one line to `Zr::Library::Ports::ALL` (`lib/zr/library/ports.rb`), and the C half in
Ruby under `lib/zr/runtime/ext`. `gem: true` vendors the gem at its version.
See [How to port a C extension](port-a-c-extension.md).

### Leave a file out

Add it to `LEFT_OUT` (ruby's library) or `GEM_EXCLUDE` (a gem) in
`tool/lib/zr/dev/vendored.rb`, with the reason. A file that zr refuses (`mkmf`,
`prism/ffi`) must not be in the tree, so that its `require` stops with
zr's reason.

## Write the tree

```console
$ bin/zr-dev vendor
```

The tool reads:

- ruby's own library from ruby's source at `RUBY_REVISION` (`RUBY_SRC`,
  see [Tools](../reference/tools.md)), as ruby's installer lays it out.
  It does not read the host's `rubylibdir`: a ruby build can patch it.
- the default gems' specifications from the running ruby. Run the tool
  on a stock ruby of the version in `.ruby-version`; it stops on another
  ruby.
- each `.gem` from rubygems.org, into `tmp/vendor/cache`. It stops when
  a file's SHA-256 is not the one in `vendor/vendor.lock`. A gem that is
  not in the lock yet must have the SHA-256 that rubygems.org publishes.
- prism's templates from its git tag (`PRISM_SRC`).

It removes the files that a source no longer has. A second run changes
nothing.

## Check the tree

```console
$ bin/zr-dev vendor --check
```

It needs no network: each file must have the SHA-256 in the lock, and
the inputs must not have changed since the lock was written.
`test/unit/vendor_test.rb` does the same check. CI also writes the tree
again from the sources and fails on a difference.

## Replace an upstream file

Do not edit a file in `vendor/`. zr's own code comes first on the load
path (`lib/zr/runtime/ext`, then `lib/zr/runtime/lib`), so a file there with the same
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

1. Install the test reference again. The expected output of each program
   test comes from ruby with the same gem versions as `vendor/`, in
   `tmp/reference/gems`. `bin/setup` also runs this step.

   ```console
   $ ruby tool/install_reference_gems.rb
   ```

2. Run the tests that the change reaches, one directory at a time:

   ```console
   $ bin/zr-dev test --changed
   ```

   If ruby gives a different output with the new version, get the new
   output from ruby with `zr-dev expect --all <path>`, as
   [How to add a program test](add-a-program-test.md) shows.

## A new ruby

zr targets the latest Ruby 4 release. A new ruby release (a new series,
or a patch release with a security fix in a default gem) is a new
toolchain. `.ruby-version` is the one place that names it. Do these
steps in order:

1. Write the new name into `.ruby-version`.
2. Check out the tag `v<name>` in `RUBY_SRC` (default `tmp/ruby`, a
   clone). For a new clone:
   `git clone --branch v<name> https://github.com/ruby/ruby tmp/ruby`.
3. Install that ruby, for example
   `mise install ruby@$(cat .ruby-version)`, then run `bundle install`.
4. Write the ruby's facts (`lib/zr/ruby_version.rb` and its runtime
   twin): `bin/zr-dev gen ruby_version`.
5. Write the tree: `bin/zr-dev vendor`. If a gem moved between the
   default and the bundled gems, first change
   `tool/lib/zr/dev/vendored.rb` and `lib/zr/library/ports.rb`.
6. Install the test reference: `ruby tool/install_reference_gems.rb`.
7. Write every generated file: `bin/zr-dev gen all`.
8. Write the expected outputs: `bin/zr-dev expect --all`. Do it again in
   the Alpine container for the `.linux.expected` files (see
   [How to test on another target](test-on-another-target.md)).
9. Run the tests. List each failure that the new ruby causes in the
   target's baseline (`test/baselines/<triple>.txt`) with its reason,
   then fix them one at a time.

The library's directory name follows the release
(`Zr::Library::Layout::API`, the same for each release of a series),
and the lock shows each file that changes. The bundled gems take the
versions in ruby's `gems/bundled_gems`. zr's library follows ruby's
releases: to get a fixed gem, release zr for the ruby release that
includes it. See also
[The pinned ruby is part of the toolchain](../explanation/the-contract.md#the-pinned-ruby-is-part-of-the-toolchain).
