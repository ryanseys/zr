# The kernel dialect

The kernel dialect is the language of `runtime/kernel/`. It has Ruby's
syntax and a machine's semantics. `Zr::Machine` (`lib/zr/machine/lower.rb`)
lowers it straight to the IR, one function for each `machine def`. Any
form outside the dialect is refused by name at its line.

To learn why the runtime has this dialect, read
[The runtime](../explanation/the-runtime.md).

## A unit

A unit is one or more files. Every declaration in a unit is visible to
every file of it, in any order, and a def may call a def of any file.
At the top level, a file holds only:

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
| `Bool` | `i8` | a comparison's answer |
| `Void` | none | no answer |

A local takes its type from its first assignment, and keeps it.

## Declarations

| Form | Declares |
|---|---|
| `sig [T1, T2] => R` then `machine def name(a, b)` | a function; required parameters only; the name is letters, digits and underscores |
| `NAME = expression` | a constant: an integer, another constant, a struct's size, or an operator over those |
| `Machine.struct :Name, field: Type, ...` | a layout; fields at natural alignment; a field of a struct type is embedded in place |
| `Machine.sig :name, [types] => type` | a signature for `Machine.call` |
| `Machine.import "name", [types] => type` | a foreign function; never variadic, never an aggregate by value |
| `Machine.import "name", [types] => type, from: "module"` | a function a wasm module imports |
| `Machine.collects :name` | a def that can run the collector; the effect spreads to every caller |
| `Machine.inline :name` | a def to copy into its callers at lowering |
| `Machine.raw "name"` | a function delivered as machine code (`zr_switch`) |

A `machine def` with the name of an import answers that import's calls,
so an OS layer can define what its libc lacks.

## Struct accessors

For `Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr`:

| Form | Answers |
|---|---|
| `RString.len(p)` | the `len` field at `p` |
| `RString.set_len(p, v)` | stores `v` into the `len` field at `p` |
| `RString.size` | the size of the layout in bytes |

## Intrinsics

| Intrinsic | Answers |
|---|---|
| `Machine.load64(p, off)`, `load32`, `load8` | a `Word`, `I32` or `I8` read at `p + off` |
| `Machine.store64(p, off, v)`, `store32`, `store8` | stores `v` at `p + off` |
| `Machine.word(x)` | `x` as a `Word`, zero-extended |
| `Machine.sword(x)` | `x` as a `Word`, sign-extended |
| `Machine.i32(x)`, `Machine.i8(x)` | `x` narrowed |
| `Machine.ptr(x)`, `Machine.value(x)` | `x` read as a `Ptr` or a `Value` |
| `Machine.f64(w)`, `Machine.bits(f)` | the same 64 bits read as the other type |
| `Machine.to_f64(w)` | a `Word`'s value as a double |
| `Machine.to_int(f)` | a double's value as a `Word`, saturated |
| `Machine.sqrt(f)`, `floor`, `ceil`, `trunc`, `nearest`, `fabs` | the `F64` operation |
| `Machine.ctz(x)`, `clz`, `popcnt`, `bswap` | the trailing or leading zeros of `x` (its width, for zero), its set bits, its bytes turned round; `x` a `Word` or an `I32`, and so the answer |
| `Machine.slot(n)` | the address of `n` bytes of the frame |
| `Machine.static(:name, n)` | the address of `n` zeroed bytes that every def naming `:name` shares |
| `Machine.gates` | the gate word, out of the register it lives in (`x28`; a global on wasm) |
| `Machine.gates_set(w)` | the gate word is `w`: its static stored and its register set, for every function at once |
| `Machine.gates_enter` | first in a def foreign code calls (`main`, a signal handler, a thread's start, a C callback): the register loaded from the static, and given back on return as the caller had it |
| `Machine.bytes("text")` | the address of a read-only copy of the literal |
| `Machine.bytesize("text")` | the literal's size in bytes |
| `Machine.id(:name)` | the symbol id of `name` |
| `Machine.addr(:name)` | the address of the `machine def` `name` |
| `Machine.extern(:name)` | the address of a data object another unit defines |
| `Machine.call(:sig, p, args...)` | a call through the pointer `p` with the named signature |

## Rules

- A call names an import or a def of the same unit, or goes through
  `Machine.call`.
- A function takes at most eight parameters, and a call passes at most
  eight arguments.
- In a def that can collect, every `Value` it holds lives in a frame
  slot the collector reads: parameters, locals, and a call's answer
  passed on to another call.
- A comparison of `Ptr`s is unsigned.

These rules are kept by convention, not by the compiler:

- A `Ptr` derived from a `Value` (a String's bytes, an Array's
  elements) is read again after any call that can run Ruby, since the
  call may have moved the storage.
- A def that can fail answers `Value`, and answers `QUNDEF` when a
  signal is pending.

## Example

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr

sig [Value] => Value
machine def zr_str_bytesize(s)
  zr_fix(RString.len(s))
end
```
