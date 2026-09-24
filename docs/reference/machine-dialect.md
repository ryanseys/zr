# The machine dialect

The machine dialect is the language of `runtime/kernel/`. It has Ruby's
syntax and a machine's semantics. `Zr::Machine`
(`lib/zr/machine/lower.rb`) lowers it directly to the IR, one function
for each `machine def`. zr refuses a form that is not in the dialect,
with a message that gives the form and the line.

`zr machine <file.rb> -o <out>` compiles one file of the dialect. To
learn why the runtime has this dialect, read
[The runtime](../explanation/the-runtime.md).

## Semantics that are different from Ruby

The syntax is Ruby's, but some forms have other meanings:

- A condition is true when its value is not 0. `0` is false.
- `/` and `%` on integers truncate, as a machine divide does.
- A `Word` is 64 bits. Arithmetic wraps at 2**64.
- A comparison of `Ptr`s is unsigned.

Thus kernel code does not run correctly under CRuby. See
[Running kernel code on the host](../explanation/the-runtime.md#running-kernel-code-on-the-host).

## A compilation unit

A compilation unit is one or more files. Every declaration in a unit
is visible to every file of the unit, in any order, and a def can call
a def of any file of the unit. At the top level, a file contains only:

- constant declarations (`NAME = expression`);
- `Machine.struct`, `Machine.sig`, `Machine.import`, `Machine.collects`,
  `Machine.inline` and `Machine.raw` declarations;
- `machine def`s, each after a `sig`.

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
| `sig [T1, T2] => R` then `machine def name(a, b)` | a function; required parameters only; the name has letters, digits and underscores |
| `NAME = expression` | a constant: an integer, another constant, the size of a struct, or an operator on these |
| `Machine.struct :Name, field: Type, ...` | a layout; each field is at its natural alignment; a field of a struct type is embedded |
| `Machine.sig :name, [types] => type` | a signature for `Machine.call` |
| `Machine.import "name", [types] => type` | a foreign function; never variadic, never an aggregate by value |
| `Machine.import "name", [types] => type, from: "module"` | a function that a WASI module imports |
| `Machine.collects :name` | a def that can run the collector; each caller then can run it too |
| `Machine.inline :name` | a def that lowering copies into its callers |
| `Machine.raw "name"` | a function that is machine code (`zr_switch`) |

A `machine def` with the name of an import takes the calls to that
import. Thus an OS layer can define a function that its libc does not
have.

## Struct accessors

For `Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr`:

| Form | Returns |
|---|---|
| `RString.len(p)` | the `len` field at `p` |
| `RString.set_len(p, v)` | stores `v` in the `len` field at `p` |
| `RString.size` | the size of the layout in bytes |

## Intrinsics

| Intrinsic | Returns or does |
|---|---|
| `Machine.load64(p, off)`, `load32`, `load8` | a `Word`, `I32` or `I8` read at `p + off` |
| `Machine.store64(p, off, v)`, `store32`, `store8` | stores `v` at `p + off` |
| `Machine.word(x)` | `x` as a `Word`, zero-extended |
| `Machine.sword(x)` | `x` as a `Word`, sign-extended |
| `Machine.i32(x)`, `Machine.i8(x)` | `x`, narrowed |
| `Machine.ptr(x)`, `Machine.value(x)` | `x` as a `Ptr` or a `Value` |
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
| `Machine.addr(:name)` | the address of the `machine def` `name` |
| `Machine.extern(:name)` | the address of a data object that another compilation unit defines |
| `Machine.call(:sig, p, args...)` | a call through the pointer `p`, with the signature `:sig` |

## Rules

zr checks these rules:

- A call goes to an import or a def of the same compilation unit, or
  through `Machine.call`.
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

## Example

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end
```
