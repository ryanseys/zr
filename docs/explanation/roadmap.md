# Roadmap

The work that is planned after the first release. A plan is not a
promise: an item can move to a later version, or go. What each release
did is in [the changelog](../../CHANGELOG.md).

## 0.2

- `--gems host`: build with the gems that the host's rubygems has
  installed.
- `zr gem install`: a gem home of zr's own, for gems that a build reads.
- racc's C port (`lib/zr/runtime/ext/racc/cparse.so.rb`): a
  `require "racc/cparse"` with no `racc/parser` before it raises
  `NameError` for `Racc::VERSION`, which ruby's C does not read. Until
  this is fixed, do not build or run racc programs locally: a check of
  it stopped a 16 GB Mac.
