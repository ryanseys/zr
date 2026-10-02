# How to port a C extension

This guide shows you how to make a gem with a C extension work in
programs that zr compiles. zr never compiles C, so the C half of the
extension becomes Ruby. To learn why, read
[Why zr has no C](../explanation/why-zr-has-no-c.md).

A gem without C needs no port: ruby 4.0.7's copy is in `vendor/ruby`,
as [How to update the vendored code](update-vendored-code.md) shows.

## 1. Vendor the gem's Ruby half

Add the gem to `ALL` in `lib/zr/library/ports.rb`, with its version and the
compat range of the Ruby halves that the port supports (`~> x.y.z` by
default):

```ruby
"digest" => port("3.2.1", gem: false),
"racc" => port("1.8.1"),
```

With `gem: true` (the default), `zr-dev vendor` puts the gem's `lib/`
and license files, as its `.gem` has them, in
`vendor/ruby/lib/ruby/gems/4.0.0/gems/<gem>-<version>/`, and a require
finds it before ruby's own library. With `gem: false`, the Ruby half is
ruby's own, in `vendor/ruby/lib/ruby/4.0.0`, and the version must be
ruby 4.0.7's. Then write the tree:

```console
$ ruby tool/zr-dev.rb vendor
```

Never edit the vendored files. If the gem does not work, fix zr. To
replace one of its files, write an overlay under `lib/zr/runtime/ext` (see
[Replace an upstream file](update-vendored-code.md#replace-an-upstream-file)).

`zr-dev reference` then installs that version for the tests. Add a
row for the gem to `THIRD_PARTY_NOTICES.md`, and to
[Library versions](../reference/differences-from-ruby.md#library-versions)
when its version is not ruby 4.0.7's.

## 2. Write the C half in Ruby

The C half is the file that the gem requires as a shared library, for
example `require "digest.so"`. Write it as `lib/zr/runtime/ext/<name>.so.rb`,
in ordinary Ruby:

```ruby
# lib/zr/runtime/ext/digest.so.rb
# digest.c, in ruby: Digest.hexencode, the Digest::Instance protocol,
# Digest::Class, and Digest::Base, ...
module Digest
  # ...
end
```

Follow the C file closely: one Ruby method for each C function that the
gem defines, with the same checks and the same error messages. Code
under `lib/zr/runtime/ext/` can call kernel defs through `Primitive`, as the
[core library](add-a-core-method.md) does.

Write everything that the C half defines, not only what the Ruby half
calls. A program can call any method of the extension.

## 3. Test a large port on CRuby first

For a large C half, write the port so that it also runs on CRuby. You
can then compare it with the real extension on the host, in one
process and object by object, before zr compiles it.
`test/unit/prism_test.rb` and `test/unit/regexp_diff_test.rb` do this
for prism and Onigmo, each over a committed sample.

## 4. Make instance variables visible

The program cannot see the instance variables that runtime code
(`lib/zr/runtime/`) writes, as with the fields of a C struct. If the gem's
Ruby half reads an instance variable that the C half sets, put
`Primitive.attr! :ivars` in the class body. Those instance variables
are then visible.

## 5. Add examples

Add program tests under `test/programs/stdlib/<gem>/` that use the gem
as its users do. Let ruby write their expected outputs, and run them:

```console
$ ruby tool/zr-dev.rb expect test/programs/stdlib/digest
$ ZR_PROGRAMS=stdlib/digest bin/minitest test/programs_test.rb
$ ruby tool/zr-dev.rb expect --check test/programs/stdlib/digest
```

`zr-dev expect --check` checks that the expected outputs are still
ruby's.

## Platform tables

If the extension needs numbers that each OS defines (errno values,
socket constants, `fcntl` flags), do not write them by hand.
`zr-dev gen tables` writes them from the ruby of each OS, into
`lib/zr/runtime/core/os/<os>/` and `lib/zr/runtime/ext/os/<os>/`.
