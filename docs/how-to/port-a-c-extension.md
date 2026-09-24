# How to port a C extension

This guide shows you how to make a gem with a C extension work in
programs that zr compiles. zr never compiles C, so the C half of the
extension becomes Ruby. To learn why, read
[Why zr has no C](../explanation/why-zr-has-no-c.md).

A gem without C needs no port: pin it, as
[How to change the version of a pinned library](bump-a-library.md)
shows.

## 1. Add the gem's Ruby half

Copy the gem's `lib/` directory, without edits, to
`vendor/ext/<gem>/lib/`. Copy its license files next to it:

```
vendor/ext/digest/
  BSDL
  COPYING
  lib/digest.rb
  lib/digest/...
```

Never edit these files. If the gem does not work, fix zr.

Add the gem's name to `GEMS` in `lib/zr/hir/build.rb`, so that a
`require` finds it. Add a row for it to `THIRD_PARTY_NOTICES.md`.

## 2. Write the C half in Ruby

The C half is the file that the gem requires as a shared library, for
example `require "digest.so"`. Write it as `runtime/ext/<name>.so.rb`,
in ordinary Ruby:

```ruby
# runtime/ext/digest.so.rb
# digest.c, in ruby: Digest.hexencode, the Digest::Instance protocol,
# Digest::Class, and Digest::Base, ...
module Digest
  # ...
end
```

Follow the C file closely: one Ruby method for each C function that the
gem defines, with the same checks and the same error messages. Code
under `runtime/ext/` can call kernel defs through `Primitive`, as the
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
(`runtime/`) writes, as with the fields of a C struct. If the gem's
Ruby half reads an instance variable that the C half sets, put
`Primitive.attr! :ivars` in the class body. Those instance variables
are then visible.

## 5. Add examples

Add examples under `test/spec/stdlib/<gem>/` that use the gem as its
users do, and run them:

```console
$ bin/test test/spec/stdlib/digest -n /sha256/
$ rake 'oracle[test/spec/stdlib/digest]'
```

`rake oracle` checks that the expected outputs are still ruby's.

## Platform tables

If the extension needs numbers that each OS defines (errno values,
socket constants, `fcntl` flags), do not write them by hand.
`rake tables` writes them from the ruby of each OS, into
`runtime/core/os/<os>/` and `runtime/ext/os/<os>/`.
