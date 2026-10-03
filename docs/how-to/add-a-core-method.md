# How to add a method to the core library

This guide shows you how to add or fix a method of a core class, such
as `String` or `Array`, in a checkout. To learn how the core library
and the kernel work together, read [The runtime](../explanation/the-runtime.md).

## 1. Write the program test first

Add a program to the class's area under `test/programs/core/`, for
example `test/programs/core/string/squeeze/squeeze_removes_runs.rb`.
Let ruby write its expected output; see
[How to add a program test](add-a-program-test.md). Then run the test:

```console
$ ruby tool/zr-dev.rb expect test/programs/core/string/squeeze
$ ZR_PROGRAMS=core/string/squeeze bin/minitest test/programs_test.rb
```

The test fails or has an error now. It is the proof of your fix. Cover the
edge cases that ruby has: empty input, a frozen receiver, the wrong
argument types, and the error messages.

## 2. Write the method in Ruby

The core library is ordinary Ruby, one file for each class, in
`lib/zr/runtime/core/`. Open the class's file and add the method:

```ruby
# lib/zr/runtime/core/string.rb
class String
  def each_byte
    return to_enum(:each_byte) { Primitive.zr_str_bytesize(self) } unless block_given?

    i = 0
    while i < Primitive.zr_str_bytesize(self)
      yield Primitive.zr_str_byte_at(self, i)
      i += 1
    end
    self
  end
end
```

Write it as CRuby's C code behaves, not as its C code reads. Match the
argument checks, the conversions (`to_str`, `to_int`) and the error
messages exactly.

## 3. Call the kernel through `Primitive`

When Ruby cannot do the work, call a kernel def:
`Primitive.zr_name(args)`. A kernel def that core code calls this way
takes only `Value`s and returns a `Value`. zr refuses a different
signature, with a message that gives the def.

Find an existing def first:

```console
$ grep -n "def zr_str_" lib/zr/runtime/kernel/string.rb
```

## 4. Add a kernel def, if you need one

Kernel defs are in `lib/zr/runtime/kernel/`, in typed Ruby. Each file
is one `module Zr::Kern`. Add a def in that module, near the defs like
it:

```ruby
# lib/zr/runtime/kernel/string.rb
module Zr::Kern
  # ...
  #: (value) -> value
  def zr_str_bytesize(s)
    zr_fix(RString[s].len)
  end
end
```

Every `def` has a `#: (types) -> type` comment on the line above it. A bare call goes only to a def. To
call a libc function, declare it in the `module Libc` of
`lib/zr/runtime/kernel/imports.rb` (`#: (types) -> type`, then
`def self.name(a, b) = Machine.import`) and call it as `Libc.name(...)`.
[The kernel subset](../reference/kernel-subset.md) lists the
types and the `Machine.*` operations.

Then write the descriptions again, because they list every kernel def:

```console
$ ZR_BLESS=1 bin/minitest test/unit/description_test.rb
```

## 5. Add a new file, if the class has none

Add a new file in `lib/zr/runtime/core/` also to `Zr::RuntimeSources::CORE_NAMES` in
`lib/zr/runtime_sources.rb`. The list is in the order that the files run, so
put a module before the classes that include it.

## 6. Run the test again

```console
$ ZR_PROGRAMS=core/string/squeeze bin/minitest test/programs_test.rb
```

The first build after a change under `lib/zr/runtime/` compiles the runtime
again, so it takes longer. Then run the class's area, to see that
nothing else changed:

```console
$ ZR_PROGRAMS=core/string bin/minitest test/programs_test.rb
$ ruby tool/zr-dev.rb affected
```

## Mark helpers and Ruby-written methods

A core method shows in a backtrace and in reflection as a C method of
CRuby does. Two marks change that. Put the mark on the first line of
the def, or alone in the class body to mark every def after it:

- `Primitive.attr! :hidden` marks a helper that CRuby has no method
  for. It adds no line to a backtrace.
- `Primitive.attr! :ruby` marks a method that CRuby itself writes in
  Ruby. `Method#parameters` then gives its parameters as CRuby does.
