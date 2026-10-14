# The runtime

Every program that zr builds includes a runtime: the heap and the
collector, method dispatch, exceptions, fibers, and all of Ruby's core
classes. In most Ruby implementations, this part is C. In zr, it is
Ruby, in three layers.

| Layer | Directory | Language |
|---|---|---|
| kernel | `lib/zr/runtime/kernel/` | typed Ruby: plain Ruby syntax, machine types |
| core library | `lib/zr/runtime/core/` | ordinary Ruby, with `Primitive` calls into the kernel |
| extensions | `lib/zr/runtime/ext/` | ordinary Ruby: the native halves of extension gems |

## Why the kernel is typed Ruby

Some code must work below Ruby's object model. The collector cannot
allocate objects to do its work. A method call cannot itself make a
method call to find its method. Code at this level needs addresses,
fixed-width integers and struct layouts.

The usual solution is C. zr uses the solution of Squeak's Slang,
RPython and Jikes RVM: write the low level in a restricted form of the
high-level language. Each kernel file is one `module Zr::Kern` of
plain Ruby. A `def` has a `#:` type comment, every local has a machine
type, a struct is a layout class, and a call is a machine call:

```ruby
module Zr::Kern
  class RString < Layout
    attr_reader :basic #: RBasic
    attr_accessor :len #: word
    attr_accessor :capa #: word
    attr_accessor :ptr #: ptr
  end

  #: (value) -> value
  def zr_str_bytesize(s)
    zr_fix(RString[s].len)
  end
end
```

Thus the whole project has one language and one compiler. The kernel
lowers to the same IR as a program, so the same backends and tests
cover it. [The kernel subset](../reference/kernel-subset.md)
lists its forms.

## Running kernel code on the host

The kernel means the same on CRuby as in a binary. `Machine::Host`
(`lib/zr/machine/host.rb`) runs the kernel's files as Ruby: a view is a
small object, an import is a call through Fiddle, and the intrinsics
are Ruby methods. The lowering refuses the forms whose meaning is
different: a condition that is not a `bool`, because CRuby takes `0`
as true, and arithmetic on a view. Thus a plain
`+ - * <<` must not overflow, and a plain `/ %` must get no negative
operand. An operation that must wrap uses `Machine.add_wrap`,
`sub_wrap`, `mul_wrap` or `shl_wrap`. A division with an operand that
can be negative uses `Machine.sdiv` or `Machine.srem`. These lower to
the same IR as the plain operators.

The tests run kernel code in three ways:

- `Harness::KernelJIT` (`test/support/harness/kernel_jit.rb`) compiles
  kernel files into one compilation unit, loads the machine code into
  the test process, and calls its functions through Fiddle. A test can
  then compare a kernel function with CRuby's. For example,
  `test/unit/zlib_check_test.rb` compares the kernel's CRC-32 and
  Adler-32 with CRuby's zlib.
- `IR::Interp` runs the IR of a typed-Ruby program without a
  backend. `test/unit/interp_test.rb` runs the programs in
  `test/machine/` this way.
- `Machine::Host` runs kernel files on CRuby.
  `test/unit/machine_host_test.rb` runs each program in `test/machine/`
  on CRuby and compares its output with the binary's, and
  `Harness::KernelHost` runs the same files as `Harness::KernelJIT`.

## Why the core library is ordinary Ruby

Most of Ruby's core library is behavior, not machinery: what
`Array#flatten` does with recursion, which conversions `String#+`
tries, and which error each method raises. Ruby shows this code most
clearly. CRuby also does this: `array.rb`, `kernel.rb` and `numeric.rb`
are Ruby with `Primitive` calls.

zr uses the same idiom. `lib/zr/runtime/core/string.rb` is plain Ruby, and it
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
includes the Ruby half without edits (in `vendor/ruby`) and
writes the C half in Ruby (`lib/zr/runtime/ext/<name>.so.rb`). The gem's own
Ruby code then runs as it does on CRuby, over a native half that gives
the same results. See
[How to port a C extension](../how-to/port-a-c-extension.md).

## The OS and machine layers

The portable kernel calls `zr_os_*` functions for everything that an
operating system does in its own way: errno, descriptors, stacks, POSIX
signals, loading code. Each OS defines all of them in
`lib/zr/runtime/kernel/os/<os>/`, and the build of a target refuses a
call that its layer does not define. On WASI,
that layer also implements the libc calls, over WASI preview 1.

The architecture layer, in `lib/zr/runtime/kernel/arch/<arch>/`, does
the same for the machine. It gives the `zr_switch` function that
switches tasks (`def zr_switch(from, to) = Machine.raw` on aarch64), the
size of a saved context (`CONTEXT_BYTES`), `zr_arch_context_start`,
which makes a context that starts a new task, and `zr_arch_context_sp`,
which reads the stack pointer that `zr_switch` saved in a context.
A continuation uses `zr_arch_context_sp` to find the low end of the
stack that it copies.

The numbers that each OS gives its constants (errno values, `fcntl`
flags, socket options) come from the ruby of that OS.
`zr-dev gen tables` writes them. Nobody types them.
