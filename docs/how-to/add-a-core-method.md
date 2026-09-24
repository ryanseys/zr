# How to add a method to the core library

This guide shows you how to add or fix a method of a core class, such
as `String` or `Array`, in a checkout. To learn how the core library
and the kernel fit together, read [The runtime](../explanation/the-runtime.md).

## 1. Write the example first

Add an example to the class's area under `test/spec/`, holding a small
program to what ruby answers. Ask ruby yourself for the answer you write
down -- it is the only source of right ones -- then run the example and
hold what you wrote to ruby again:

```console
$ bundle exec minitest test/spec/core/string -n /squeeze/
$ rake 'oracle[test/spec/core/string]'
```

The example diverges or refuses to build now. It is the proof of your fix.
Cover the edge cases ruby has: empty input, a frozen receiver, the wrong
argument types, and the error messages.

## 2. Write the method in Ruby

The core library is ordinary Ruby, one file for each class, in
`runtime/core/`. Open the class's file and add the method:

```ruby
# runtime/core/string.rb
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

## 3. Reach the kernel through `Primitive`

When Ruby cannot do the work, call a kernel def: `Primitive.zr_name(args)`.
A kernel def that core code calls this way takes only `Value`s and
answers a `Value`. zr refuses any other shape by name.

Find an existing def first:

```console
$ grep -n "machine def zr_str_" runtime/kernel/string.rb
```

## 4. Add a kernel def, if you need one

Kernel defs are in `runtime/kernel/`, in the kernel dialect. Add one beside
its kin:

```ruby
# runtime/kernel/string.rb
sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end
```

Every `machine def` follows a `sig`. The
[kernel dialect reference](../reference/kernel-dialect.md) lists the
types and the `Machine.*` operations.

Then write the eval descriptions again, since they list every kernel
def:

```console
$ ZR_BLESS=1 rake test:unit N=/Description/
```

## 5. Add a new file, if the class has none

A new file in `runtime/core/` must also go into `Zr::CORE_NAMES` in
`lib/zr/runtime.rb`. The list is in the order the files run, so put a
module before the classes that include it.

## 6. Run the case again

```console
$ ruby -Ilib -Itest test/spec/core/string/string_test.rb -n "/squeeze/"
```

The first build after a change under `runtime/` compiles the runtime again,
so it takes longer. Then run the class's directory, to see that nothing
else changed:

```console
$ rake test:spec N=/string/
```

## Mark helpers and Ruby-written methods

A core method shows in a backtrace and in reflection as a C method of
CRuby's does. Two marks change that. Put the mark as the first line of
the def, or alone in the class body to mark every def after it:

- `Primitive.attr! :hidden` marks a helper that CRuby has no method
  for. It leaves no backtrace row.
- `Primitive.attr! :ruby` marks a method that CRuby itself writes in
  Ruby. `Method#parameters` then answers its parameters as CRuby's
  does.
