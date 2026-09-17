# How to port a C extension

This guide shows you how to make a gem with a C extension work in
programs ze0 compiles. ze0 never compiles C, so the C half of the
extension becomes Ruby. To learn why, read
[Why ze0 has no C](../explanation/why-ze0-has-no-c.md).

## 1. Vendor the gem's Ruby half

Copy the gem's `lib/` directory, unedited, to `vendor/ext/<gem>/lib/`.
Copy its license files beside it:

```
vendor/ext/digest/
  BSDL
  COPYING
  lib/digest.rb
  lib/digest/...
```

Never edit these files. If the gem does not work, fix ze0.

Add the gem's name to `GEMS` in `lib/ze0/hir/build.rb`, so that a
`require` finds it. Add a row for it to `THIRD_PARTY_NOTICES.md`.

## 2. Write the C half in Ruby

The C half is the file the gem requires as a shared library, for
example `require "digest.so"`. Write it as `rt/ext/<name>.so.rb`, in
ordinary Ruby:

```ruby
# rt/ext/digest.so.rb
# digest.c, in ruby: Digest.hexencode, the Digest::Instance protocol,
# Digest::Class, and Digest::Base, ...
module Digest
  # ...
end
```

Follow the C file closely: one Ruby method for each C function the gem
defines, with the same checks and the same error messages. Code under
`rt/ext/` can call kernel defs through `Primitive`, as the
[core library](add-a-core-method.md) does.

Provide everything the C half defines, not only what the Ruby half
calls. A program can call any method of the extension.

## 3. Put a large port under test on ruby first

For a large C half, write the port so that it also runs on CRuby. Then
compare it with the real extension on the host, case by case, before
ze0 compiles it. `tools/zlib_diff.rb`, `tools/regexp_diff.rb` and
`tools/prism_diff.rb` do this for zlib, Onigmo and prism.

## 4. Mind instance variables

Instance variables that runtime code (`rt/`) writes are hidden from the
program, as a C struct's fields are. When the gem's Ruby half reads an
instance variable that the C half sets, put `Primitive.attr! :ivars` in
the class body, so those instance variables stay visible.

## 5. Add cases

Record cases under `test/stdlib/<gem>/` that use the gem as its users
do, and run them:

```console
$ ruby tools/record.rb stdlib/digest/sha256_of_a_file.rb
$ bin/ze0 test stdlib/digest/
```

## Platform tables

When the extension needs numbers that each OS defines (errno values,
socket constants, `fcntl` flags), do not write them by hand. The table
tools in `tools/` write them from the ruby of each OS, into
`rt/core/os/<os>/` and `rt/ext/os/<os>/`.
