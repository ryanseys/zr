# The runtime

Every program that zr builds includes a runtime: the heap and the
collector, method dispatch, exceptions, fibers, and all of Ruby's core
classes. In most Ruby implementations, this part is C. In zr, it is
Ruby, in three layers.

| Layer | Directory | Language |
|---|---|---|
| kernel | `runtime/kernel/` | the machine dialect: Ruby syntax, machine semantics |
| core library | `runtime/core/` | ordinary Ruby, with `Primitive` calls into the kernel |
| extensions | `runtime/ext/` | ordinary Ruby: the native halves of extension gems |

## Why the kernel is a dialect

Some code must work below Ruby's object model. The collector cannot
allocate objects to do its work. A method call cannot itself make a
method call to find its method. Code at this level needs addresses,
fixed-width integers and struct layouts.

The usual solution is C. zr uses the solution of Squeak's Slang,
RPython and Jikes RVM: write the low level in a restricted form of the
high-level language. A `machine def` has Ruby's syntax, but every
local has a machine type, a struct is a layout, and a call is a
machine call:

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end
```

Thus the whole project has one language and one compiler. The kernel
lowers to the same IR as a program, so the same backends and tests
cover it. [The machine dialect](../reference/machine-dialect.md) lists
its forms.

## Running kernel code on the host

The machine dialect gives Ruby syntax other meanings: `0` is false, `/`
truncates, and words wrap at 2**64. Thus kernel code does not run
correctly under CRuby. zr compiles it first.

The tests run kernel code in two ways:

- `Harness::KernelJIT` (`test/support/harness/kernel_jit.rb`) compiles
  kernel files into one compilation unit, loads the machine code into
  the test process, and calls its functions through Fiddle. A test can
  then compare a kernel function with CRuby's. For example,
  `test/unit/zlib_check_test.rb` compares the kernel's CRC-32 and
  Adler-32 with CRuby's zlib.
- `IR::Interp` runs the IR of a machine-dialect program without a
  backend. `test/unit/interp_test.rb` runs the programs in
  `test/machine/` this way.

## Why the core library is ordinary Ruby

Most of Ruby's core library is behavior, not machinery: what
`Array#flatten` does with recursion, which conversions `String#+`
tries, and which error each method raises. Ruby shows this code most
clearly. CRuby also does this: `array.rb`, `kernel.rb` and `numeric.rb`
are Ruby with `Primitive` calls.

zr uses the same idiom. `runtime/core/string.rb` is plain Ruby, and it
calls the kernel through `Primitive`:

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
CRuby's C methods do: they show in backtraces as C methods, a
`TracePoint` does not see their lines, and the program cannot see the
instance variables that they write, as with the fields of a C struct.

## Why extensions are Ruby too

A gem such as `json` or `digest` has a Ruby half and a C half. zr
includes the Ruby half without edits (`vendor/ext/<gem>/lib`) and
writes the C half in Ruby (`runtime/ext/<name>.so.rb`). The gem's own
Ruby code then runs as it does on CRuby, over a native half that gives
the same results. See
[How to port a C extension](../how-to/port-a-c-extension.md).

## The OS and machine layers

The portable kernel calls a fixed list of functions for everything
that an operating system does in its own way: errno, descriptors,
stacks, POSIX signals, loading code. `runtime/kernel/os.rb` gives the
list, and each OS implements it in `runtime/kernel/os/<os>/`. On WASI,
that layer also implements the libc calls, over WASI preview 1.

The numbers that each OS gives its constants (errno values, `fcntl`
flags, socket options) come from the ruby of that OS.
`zr-dev gen tables` writes them. Nobody types them.
