# How to change the version of a pinned library

This guide shows you how to change one of ruby's pure-Ruby libraries,
such as `csv` or `uri`, to a different version. zr reads these
libraries from installed gems and compiles them into programs.
`PINS` in `lib/zr/libraries.rb` pins each gem to one version, and
`zr.gemspec` reads its dependencies from `PINS`.
`lib/zr/library_digests.rb` records the digests of the files of each
version.

A gem with a C extension is different: see
[How to port a C extension](port-a-c-extension.md).

## 1. Change the pin

Change the version in `PINS` in `lib/zr/libraries.rb`.

To add a new library, add its gem to `PINS`. zr reads the files in the
gem's `require_paths`.

rubygems and bundler are different. They are in `HOST`, not in
`PINS`, and the gemspec does not depend on them. zr reads them from
ruby's own library directory (`RbConfig::CONFIG["rubylibdir"]`): the
file `rubygems.rb` or `bundler.rb`, and the files under the directory
of the same name. A new ruby can change their versions. Change `HOST`
to the versions that `Gem::VERSION` and `Bundler::VERSION` give in a
stock ruby.

## 2. Lock and install

```console
$ bundle lock
$ bundle install
```

Commit `Gemfile.lock` with the change.

## 3. Write the digests again

```console
$ ruby tool/zr-dev.rb gen libraries
```

The generator finds each pinned gem as a build does, and writes the SHA-256
digest of its files. A build refuses a gem whose files do not have
this digest. Thus a build before this step stops, with a message that
gives the gem.

## 4. Run the tests that the change reaches

```console
$ ruby tool/zr-dev.rb affected
```

A change to the pins reaches every spec. If ruby gives a different
output for a program with the new version, get the new output from
ruby, as [How to add a spec](add-a-spec.md) shows.

## A new ruby

A new ruby changes every pin. Pin each default and bundled gem to the
version that the new ruby includes (`gem list` shows them), and set
`HOST` to its rubygems and bundler versions. Copy the
files that `vendor/lib/VERSIONS` lists from the new ruby, without
edits. See also
[The pinned ruby is part of the toolchain](../explanation/the-contract.md#the-pinned-ruby-is-part-of-the-toolchain).
