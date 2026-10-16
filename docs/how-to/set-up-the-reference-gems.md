# How to set up the reference gems

Every expected output of a test comes from the ruby that `.ruby-version`
names (`test/support/harness/reference.rb`). That ruby runs with the gems
of its own install, and without this checkout's bundle, `RUBYOPT` or
`RUBYLIB`. zr installs nothing for it: you choose which gems it sees.

## Use the pinned ruby as installed

A stock install of the pinned ruby has its default and bundled gems at
their own versions. That is enough for most tests. A test whose output
depends on a gem that the install does not have prints ruby's
`LoadError`, and zr's answer is compared with that.

When `vendor/` carries another version of a gem than the install has (a
port at zr's version, see `lib/zr/library/ports.rb`), install that
version into the pinned ruby, so both sides load the same code:

```console
$ gem install json -v 3.0.2
```

## Use a GEM_HOME of your own

To keep the reference apart from the gems that you install for other
work, fill a directory and name it in `ZR_REFERENCE_GEM_HOME`. The
reference ruby then uses it as its `GEM_HOME` and `GEM_PATH`. Default gems
still load from ruby's own install.

```console
$ gem install --install-dir ~/zr-reference --no-document json:3.0.2 rbs:4.2.0
$ export ZR_REFERENCE_GEM_HOME=~/zr-reference
$ bin/zr-dev expect test/programs/stdlib/json
```

Record and check with the same set of gems: an output that a recording
took with one set can differ with another.
