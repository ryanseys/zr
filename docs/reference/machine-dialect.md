# The kernel's typed Ruby

The kernel (`lib/zr/runtime/kernel/`) is plain Ruby with types. Each
file is one `module Zr::Kern`. Each def comes after a `sig` that gives
its types. `Zr::Machine` (`lib/zr/machine/lower.rb`) lowers each def
directly to one IR function. zr refuses a form that the typed lowering
does not have, with a message that gives the form and the line.

`zr machine <file.rb> -o <out>` compiles one kernel file. To learn why
the runtime has this form, read
[The runtime](../explanation/the-runtime.md).

## Semantics that are different from Ruby

The syntax is Ruby's, but some forms have other meanings:

- A condition is true when its value is not 0. `0` is false.
- `/` and `%` on integers truncate, as a machine divide does.
- A `Word` is 64 bits. Arithmetic wraps at 2**64.
- A comparison of `Ptr`s is unsigned.

The goal is that kernel code means the same on CRuby. For this, the
kernel obeys two rules that zr does not check yet:

- A plain `+`, `-`, `*` or `<<` does not overflow. An operation that
  must wrap uses `Machine.add_wrap`, `sub_wrap`, `mul_wrap` or
  `shl_wrap`.
- A plain `/` or `%` gets no negative operand. A division with an
  operand that can be negative uses `Machine.sdiv` or `Machine.srem`.

These intrinsics lower to the same IR as the plain operators. At
present, kernel code does not run under CRuby. See
[Running kernel code on the host](../explanation/the-runtime.md#running-kernel-code-on-the-host).

## A compilation unit

A compilation unit is one or more files. Every declaration in a unit
is visible to every file of the unit, in any order, and a def can call
a def of any file of the unit.

A file is one `module Zr::Kern ... end`. zr refuses a file with a
different module, or with statements outside the module. In the
module, a file contains only:

- constant declarations (`NAME = expression`);
- layouts (`Name = layout ...`) and signatures (`Name = fn ...`);
- `Libc.import`, `inline`, `collects` and `raw` declarations;
- `def`s, each after a `sig`.

## Types

| Type | IR type | Meaning |
|---|---|---|
| `Word` | `i64` | a 64-bit integer |
| `I32` | `i32` | a 32-bit integer |
| `I8` | `i8` | a byte |
| `Ptr` | `i64` | an address |
| `Value` | `i64` | a tagged Ruby value; see [Runtime layouts](runtime-layouts.md) |
| `F64` | `f64` | a double |
| `Bool` | `i8` | the result of a comparison: 0 or 1 |
| `Void` | none | no value |

A local gets its type from its first assignment, and keeps it.

## Declarations

| Form | Declares |
|---|---|
| `sig [T1, T2] => R` then `def name(a, b)` | a function; required parameters only; no receiver; the name has letters, digits and underscores |
| `NAME = expression` | a constant: an integer, another constant, the size of a layout, or an operator on these |
| `Name = layout field: Type, ...` | a layout; each field is at its natural alignment; a field of a layout type is embedded |
| `Name = fn [types] => type` | a signature for `Name.call` |
| `Libc.import :name, [types] => type` | a foreign function, called as `Libc.name(...)`; never variadic, never an aggregate by value |
| `Libc.import :name, [types] => type, from: "module"` | a function that a WASI module imports |
| `collects :name` | a def that can run the collector; each caller then can run it too |
| `inline :name` | a def that lowering copies into its callers |
| `raw :name, [types] => type` | a function that the backend gives as machine code; the only one is `raw :zr_switch, [Ptr, Ptr] => Void` |

A def with the name of an import takes the calls to that import, and
must have the same signature. Thus an OS layer can define a function
that its libc does not have.

Lowering also copies a small def into its callers when the def cannot
run the collector and has no `while` or `break`. `inline :name` is
necessary only for a larger def.

## Calls

| Form | Calls |
|---|---|
| `name(args...)` | a def of the unit, or a raw function; never an import |
| `Libc.name(args...)` | an import, or the def that takes the calls to that import |
| `Name.call(p, args...)` | the function at the pointer `p`, with the signature `Name` |

## Layout accessors

For `RString = layout basic: RBasic, len: Word, capa: Word, ptr: Ptr`:

| Form | Returns |
|---|---|
| `RString.len(p)` | the `len` field at `p` |
| `RString.set_len(p, v)` | stores `v` in the `len` field at `p` |
| `RString.basic(p)` | the address of the embedded `basic` field |
| `RString.size` | the size of the layout in bytes |

## Intrinsics

| Intrinsic | Returns or does |
|---|---|
| `Machine.load64(p, off)`, `load32`, `load8` | a `Word`, `I32` or `I8` read at `p + off` |
| `Machine.store64(p, off, v)`, `store32`, `store8` | stores `v` at `p + off` |
| `Machine.word(x)` | a `Ptr` or a `Value` as a `Word`, or the bits of a literal at or above 2**63; zr refuses an `I8` or an `I32` |
| `Machine.u8(x)`, `Machine.u32(x)` | an `I8` or an `I32` as a `Word`, zero-extended; zr refuses another type |
| `Machine.sword(x)` | `x` as a `Word`, sign-extended |
| `Machine.i32(x)`, `Machine.i8(x)` | `x`, narrowed |
| `Machine.ptr(x)`, `Machine.value(x)` | `x` as a `Ptr` or a `Value` |
| `Machine.add_wrap(a, b)`, `sub_wrap`, `mul_wrap`, `shl_wrap` | `a + b`, `a - b`, `a * b` or `a << b`, for a `Word` operation that must wrap into the signed range |
| `Machine.uadd_wrap(a, b)`, `usub_wrap`, `umul_wrap`, `ushl_wrap` | the same for a `Ptr`, which wraps into [0, 2**64) |
| `Machine.sdiv(a, b)`, `Machine.srem(a, b)` | `a / b` or `a % b` (truncated), for an operand that can be negative; `a` and `b` are the same integer type |
| `Machine.f64(w)`, `Machine.bits(f)` | the same 64 bits as the other type |
| `Machine.to_f64(w)` | the value of a `Word` as a double |
| `Machine.to_int(f)` | the value of a double as a `Word`, saturated |
| `Machine.sqrt(f)`, `floor`, `ceil`, `trunc`, `nearest`, `fabs` | the `F64` operation |
| `Machine.ctz(x)`, `clz`, `popcnt`, `bswap` | the trailing or leading zeros of `x` (its width, for zero), its set bits, or its bytes in reverse order; `x` and the result are a `Word` or an `I32` |
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
- In a def that can collect, every `Value` is in a frame slot that the
  collector reads: parameters, locals, and the result of a call that
  goes to another call.

zr does not check these rules. Obey them:

- Read a `Ptr` that comes from a `Value` (the bytes of a String, the
  elements of an Array) again after a call that can run Ruby. The call
  can move the storage.
- A def that can fail returns `Value`, and returns `QUNDEF` when an
  unwind is pending.
- A plain `+ - * <<` does not overflow, and a plain `/ %` gets no
  negative operand. Use the `_wrap` intrinsics and `sdiv`/`srem`.

## Example

```ruby
module Zr::Kern
  Libc.import :memmove, [Ptr, Ptr, Word] => Ptr

  RString = layout basic: RBasic, len: Word, capa: Word, ptr: Ptr

  sig [Value] => Value
  def zr_str_bytesize(s)
    zr_fix(RString.len(s))
  end
end
```

## The rewrite from the old form

The kernel was in a "machine dialect" before: top-level statements,
`machine def`, `Machine.import "f"` with bare calls to imports,
`Machine.struct`, `Machine.sig` with `Machine.call`, and
`Machine.inline`, `Machine.collects` and `Machine.raw "zr_switch"`.
`tool/kern_rewrite.rb` rewrote each kernel file to the plain form.
`zr-dev golden check` (`tool/golden.rb`) shows that the lowering of the
kernel stays the same. A generator that writes a file below
`lib/zr/runtime/kernel/` (`tool/lib/zr/dev/files.rb`) puts its output
through the same rewrite.
