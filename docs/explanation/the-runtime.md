# The runtime

Every program zr builds carries a runtime: the heap and collector,
method dispatch, exceptions, fibers, and all of Ruby's core classes. In
most Ruby implementations this part is C. In zr it is Ruby, in three
layers.

| Layer | Directory | Written in |
|---|---|---|
| kernel | `runtime/kernel/` | the kernel dialect: Ruby syntax, machine semantics |
| core library | `runtime/core/` | ordinary Ruby, with `Primitive` calls into the kernel |
| extensions | `runtime/ext/` | ordinary Ruby: the native halves of extension gems |

## Why the kernel is a dialect

Some code must work below Ruby's object model. The collector cannot
allocate objects to do its work. A method call cannot itself make a
method call to find its method. Code at this level needs addresses,
fixed-width integers and struct layouts.

The usual answer is C. zr takes the answer of Squeak's Slang, RPython
and Jikes RVM instead: write the low level in a restricted form of the
high-level language. A `machine def` has Ruby's syntax, but every local
has a machine type, a struct is a layout, and a call is a machine call:

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end
```

This keeps the whole project in one language, and one compiler. The
kernel lowers to the same IR as a program, so the same backends and
checks cover it. The [kernel dialect reference](../reference/kernel-dialect.md)
lists its forms.

## Why the core library is ordinary Ruby

Most of Ruby's core library is behaviour, not machinery: what
`Array#flatten` does with recursion, which conversions `String#+`
tries, and which error each method raises. That code is clearest in
Ruby. CRuby itself moves in this direction: `array.rb`, `kernel.rb`
and `numeric.rb` are Ruby with `Primitive` calls.

zr follows the same idiom. `runtime/core/string.rb` is plain Ruby, and it
reaches the kernel through `Primitive`:

```ruby
def each_byte
  return to_enum(:each_byte) { Primitive.zr_str_bytesize(self) } unless block_given?

  i = 0
  while i < Primitive.zr_str_bytesize(self)
    yield Primitive.zr_str_byte_at(self, i)
    i += 1
  end
  self
end
```

A `Primitive` call is a direct call of a kernel def, with no dispatch.
The hot paths (string bytes, array storage, hash lookup, integer and
float arithmetic) are kernel defs. The rules are in Ruby.

The core library compiles in an internal mode. Its methods behave as
CRuby's C methods do: they show in backtraces as C methods do, a
`TracePoint` does not see their lines, and the instance variables they
write are hidden from the program, as a C struct's fields are.

## Why extensions are Ruby too

A gem such as `json` or `digest` has a Ruby half and a C half. zr
vendors the Ruby half unedited (`vendor/ext/<gem>/lib`) and writes the
C half as Ruby (`runtime/ext/<name>.so.rb`). The gem's own Ruby code then
runs exactly as it does on CRuby, over a native half that answers the
same way. See [How to port a C extension](../how-to/port-a-c-extension.md).

## The OS and machine layers

The portable kernel calls a fixed list of functions for everything an
operating system does in its own way: errno, descriptors, stacks,
signals, loading code. `runtime/kernel/os.rb` names the list, and each OS
implements it under `runtime/kernel/os/<os>/`. On WASI, that layer also
implements the libc calls themselves, over WASI preview 1.

The numbers each OS gives its constants (errno values, `fcntl` flags,
socket options) come from that OS's ruby, written by the table tools.
Nobody types them.
