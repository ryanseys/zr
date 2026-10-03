# The kernel subset

The kernel (`lib/zr/runtime/kernel/`) is a typed subset of Ruby. Each
file is one `module Zr::Kern`. Each def has a `#:` comment above it
that gives its types, in inline RBS: `#: (i32, ptr) -> i32`.
`Zr::Machine` (`lib/zr/machine/lower.rb`) lowers each def directly to
one IR function. zr refuses a form that the subset does not have, with
a message that gives the form and the line.

To learn why the runtime has this form, read
[The runtime](../explanation/the-runtime.md).

## The same meaning on CRuby

The kernel is Ruby, and CRuby runs it too (`Machine::Host`,
`lib/zr/machine/host.rb`). The subset keeps the meaning of each form the
same on CRuby and in a binary:

- A condition is a `bool`: a comparison, `!`, `&&` or `||` of
  comparisons. zr refuses a condition of another type, because CRuby
  takes `0` as true. Compare the value: `x != 0`.
- A view (`RString[s]`) is an object on CRuby and an address in a
  binary. zr refuses arithmetic on a view and a view where a `ptr` is
  necessary. `Machine.ptr(view)` gives its address.
- `Machine.ctz`, `clz`, `popcnt` and `bswap` take a `word`. CRuby has no
  32-bit integer, so widen an `i32` first (`Machine.u32`).

The kernel also obeys two rules that only the checked build
(`ZR_KERNEL_CHECKED`) checks:

- A plain `+`, `-`, `*` or `<<` does not overflow. An operation that
  must wrap uses `Machine.add_wrap`, `sub_wrap`, `mul_wrap` or
  `shl_wrap`.
- A plain `/` or `%` gets no negative operand. A division with an
  operand that can be negative uses `Machine.sdiv` or `Machine.srem`.

These intrinsics lower to the same IR as the plain operators.

## A compilation unit

A compilation unit is one or more files. Every declaration in a unit
is visible to every file of the unit, in any order, and a def can call
a def of any file of the unit.

A file is one `module Zr::Kern ... end`. zr refuses a file with a
different module, or with statements outside the module. In the
module, a file contains only:

- constants (`NAME = expression`);
- layouts (`class Name < Layout`);
- imports (`module Libc`) and signatures (`module Name`);
- `inline` and `collects` declarations;
- `def`s, each with a `#: (types) -> type` comment on the line above.

## Types

| Type | IR type | Meaning |
|---|---|---|
| `word` | `i64` | a 64-bit integer |
| `i32` | `i32` | a 32-bit integer |
| `i8` | `i8` | a byte |
| `ptr` | `i64` | an address |
| `value` | `i64` | a tagged Ruby value; see [Runtime layouts](runtime-layouts.md) |
| `f64` | `f64` | a double |
| `bool` | `i8` | the result of a comparison: 0 or 1 |
| `void` | none | no value; a return type only |
| a layout, such as `RBasic` | `i64` | a view of that layout |

The types are RBS: `sig/zr/kern.rbs` declares each name, the `Layout`
class and each intrinsic, and `bool` and `void` are RBS's own. So RBS
reads each `#:` comment of the kernel (`test/unit/kern_rbs_test.rb`),
and Steep checks the kernel of each target at the strict level
(`test/unit/kernel_steep_test.rb`): each call, field, import, signature
and intrinsic.

Steep does not keep the type of a local that a loop assigns when an
earlier loop assigned it too. A `# @type var name: type` line at the
start of the def gives Steep that type; the lowering does not read it.

A `word` and a `ptr` fit each other. A view fits only a view of the same
layout. A local gets its type from its first assignment, and keeps it.

## Declarations

| Form | Declares |
|---|---|
| `#: (t1, t2) -> r` then `def name(a, b)` | a function; required parameters only; no receiver; the name has letters, digits and underscores |
| `NAME = expression` | a constant: an integer, another constant, the size of a layout, or an operator on these |
| `class Name < Layout` | a layout: one `attr_accessor :field #: type` for each field, in order, each at its natural alignment; a field of a layout type is embedded, and has an `attr_reader` |
| `module Libc` | imports: each one is `#: (types) -> type` then `def self.name(a, b) = Machine.import`; never variadic, never an aggregate by value |
| `def self.name(a) = Machine.import(from: "module")` in `module Libc` | a function that a WASI module imports |
| `module Name` | a signature: one `#: (ptr, types) -> type` then `def self.call(fn, a, b) = Machine.indirect` |
| `collects :name` | a def that can run the collector; each caller then can run it too |
| `inline :name` | a def that lowering copies into its callers |
| `#: (types) -> type` then `def name(a, b) = Machine.raw` | a function that the backend gives as machine code; the only one is `zr_switch`, `(ptr, ptr) -> void` |

Each layer of the kernel has its imports in one file: `kernel/imports.rb`
for the portable kernel, and `kernel/os/<os>/imports.rb` for an OS layer.
zr refuses an import that a unit declares twice.

A def with the name of an import takes the calls to that import, and
must have the same type. Thus an OS layer can define a function that
its libc does not have.

Lowering also copies a small def into its callers when the def cannot
run the collector and has no `while` or `break`. `inline :name` is
necessary only for a larger def.

## Calls

| Form | Calls |
|---|---|
| `name(args...)` | a def of the unit, or a raw function; never an import |
| `Libc.name(args...)` | an import, or the def that takes the calls to that import |
| `Name.call(p, args...)` | the function at the pointer `p`, with the signature `Name` |

## Views

For this layout:

```ruby
class RString < Layout
  attr_reader :basic #: RBasic
  attr_accessor :len #: word
  attr_accessor :capa #: word
  attr_accessor :ptr #: ptr
end
```

| Form | Gives |
|---|---|
| `RString[p]` | a view of the `RString` at `p`, which is a `value`, a `ptr`, a `word` or another view |
| `RString[p].len` | the `len` field |
| `RString[p].len = v` | stores `v` in the `len` field |
| `RString[p].basic` | a view of the embedded `RBasic` |
| `RString.size` | the size of the layout in bytes |

A view can be a local (`str = RString[s]`), a parameter or a return
value (`#: (RBasic) -> void`). In a binary a view is its address, so a
view costs nothing.

## Intrinsics

| Intrinsic | Returns or does |
|---|---|
| `Machine.load64(p, off)`, `load32`, `load8` | a `word`, `i32` or `i8` read at `p + off` |
| `Machine.store64(p, off, v)`, `store32`, `store8` | stores `v` at `p + off` |
| `Machine.word(x)` | a `ptr` or a `value` as a `word`, or the bits of a literal at or above 2**63; zr refuses an `i8` or an `i32` |
| `Machine.u8(x)`, `Machine.u32(x)` | an `i8` or an `i32` as a `word`, zero-extended; zr refuses another type |
| `Machine.sword(x)` | `x` as a `word`, sign-extended |
| `Machine.i32(x)`, `Machine.i8(x)` | `x`, narrowed |
| `Machine.ptr(x)`, `Machine.value(x)` | `x` as a `ptr` or a `value`; `Machine.ptr(view)` is the view's address |
| `Machine.add_wrap(a, b)`, `sub_wrap`, `mul_wrap`, `shl_wrap` | `a + b`, `a - b`, `a * b` or `a << b`, for a `word` operation that must wrap into the signed range |
| `Machine.uadd_wrap(a, b)`, `usub_wrap`, `umul_wrap`, `ushl_wrap` | the same for a `ptr`, which wraps into [0, 2**64) |
| `Machine.sdiv(a, b)`, `Machine.srem(a, b)` | `a / b` or `a % b` (truncated), for an operand that can be negative; `a` and `b` are the same integer type |
| `Machine.f64(w)`, `Machine.bits(f)` | the same 64 bits as the other type |
| `Machine.to_f64(w)` | the value of a `word` as a double |
| `Machine.to_int(f)` | the value of a double as a `word`, saturated |
| `Machine.sqrt(f)`, `floor`, `ceil`, `trunc`, `nearest`, `fabs` | the `f64` operation |
| `Machine.ctz(x)`, `clz`, `popcnt`, `bswap` | the trailing or leading zeros of the `word` `x` (64, for zero), its set bits, or its bytes in reverse order |
| `Machine.slot(n)` | the address of `n` bytes of the frame |
| `Machine.static(:name, n)` | the address of `n` zeroed bytes that every def that uses `:name` shares |
| `Machine.gates` | the gate word, from its register (`x28`; a global on wasm) |
| `Machine.gates_set(w)` | sets the gate word to `w`: stores its static and sets its register, for all functions |
| `Machine.gates_enter` | the first statement of a def that foreign code calls (`main`, a signal handler, the start of a thread, a C callback): loads the register from the static, and gives the caller's value back on return |
| `Machine.bytes("text")` | the address of a read-only copy of the literal |
| `Machine.bytesize("text")` | the size of the literal in bytes |
| `Machine.id(:name)` | the symbol ID of `name` |
| `Machine.addr(:name)` | the address of the def `name` |
| `Machine.extern(:name)` | the address of a data object that another compilation unit defines |

## Rules

zr checks these rules:

- A bare call goes to a def of the same compilation unit or to a raw
  function. A call to an import is `Libc.name(...)`. A call through a
  pointer is `Name.call(p, ...)`.
- A function has at most eight parameters, and a call has at most
  eight arguments.
- In a def that can collect, every `value` is in a frame slot that the
  collector reads: parameters, locals, and the result of a call that
  goes to another call.

zr does not check these rules. Obey them:

- Read a `ptr` that comes from a `value` (the bytes of a String, the
  elements of an Array) again after a call that can run Ruby. The call
  can move the storage.
- A def that can fail returns `value`, and returns `QUNDEF` when an
  unwind is pending.

## Example

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

## The rewrites from the older forms

The kernel was in a "machine dialect" first: top-level statements,
`machine def`, `Machine.import "f"` with bare calls to imports,
`Machine.struct`, `Machine.sig` with `Machine.call`, and
`Machine.inline`, `Machine.collects` and `Machine.raw "zr_switch"`.
Then it was plain Ruby with its own declaration calls:
`Name = layout field: Type`, `Name.field(p)`, `Libc.import :name,
[types] => type`, `Name = fn [types] => type` and `raw :zr_switch`.
A one-off script rewrote each kernel file at each step, and
`zr-dev golden check` (`tool/golden.rb`) showed that the lowering of
the kernel stayed the same.
