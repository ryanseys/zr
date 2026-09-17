# Runtime layouts

The runtime's values and objects, as `rt/kernel/` declares them. The
declarations are the source of truth; this page lists the main ones.
To learn how the collector and dispatch use them, read
[Memory and the collector](../explanation/memory-and-the-collector.md)
and [Method dispatch and signals](../explanation/method-dispatch-and-signals.md).

## Values

A `Value` is a 64-bit word with CRuby's tagging (`rt/kernel/value.rb`).

| Value | Encoding |
|---|---|
| `false` | `0x00` |
| `nil` | `0x08` |
| `true` | `0x14` |
| undef | `0x34`: never reaches Ruby; it means a signal is pending |
| Integer (fixnum) | `n << 1 \| 1` |
| Float (flonum) | low bits `10`, CRuby's rotation |
| Symbol (static) | `id << 8 \| 0x0c` |
| any other object | a nonzero, 8-aligned pointer to a cell that starts with `RBasic` |

`nil.object_id` is 8, and `1.0.equal?(1.0)` is true, as in CRuby.

## The object header

```ruby
Machine.struct :RBasic, flags: Word, klass: Value
```

| Bits of `flags` | Meaning |
|---|---|
| 0-4 | the type (`T_MASK = 31`) |
| 5 | `FL_ALLOCATED` |
| 6 | `FL_MARK` |
| 10 | `FL_EXIVAR` |
| 11 | `FL_FREEZE` |
| 12 | `FL_SINGLETON` |
| 24-31 | the encoding index, where the object has an encoding |

| Type | Number | Type | Number |
|---|---|---|---|
| `T_OBJECT` | 1 | `T_EXCEPTION` | 24 |
| `T_CLASS` | 2 | `T_CREF` | 25 |
| `T_MODULE` | 3 | `T_ENV` | 26 |
| `T_FLOAT` | 4 | `T_PROC` | 27 |
| `T_STRING` | 5 | `T_ICLASS` | 28 |
| `T_ARRAY` | 7 | `T_METHOD` | 29 |
| `T_HASH` | 8 | `T_FIBER` | 30 |
| | | `T_REGEXP` | 31 |

## Objects

```ruby
Machine.struct :RString, basic: RBasic, len: Word, capa: Word, ptr: Ptr
Machine.struct :RArray, basic: RBasic, len: Word, capa: Word, ptr: Ptr, base: Ptr
Machine.struct :RObject, basic: RBasic, iv: IvTab
Machine.struct :RProc, basic: RBasic, fn: Ptr, meta: Ptr, env: Value, self: Value, cref: Value,
               blk: Value, home: Ptr, serial: Word, site: Word, ret_home: Ptr, ret_serial: Word,
               spread: Word, lambda: Word, passed: Word
Machine.struct :REnv, basic: RBasic, parent: Value, slots: Ptr, nslots: Word, names: Ptr, cell: Value, home: Ptr
```

- A String's bytes and an Array's elements stay in the object's cell
  while they fit, and move to a malloc'd block when they grow. `ptr`
  points at them in both cases.
- An object's instance variables are a table of `(id, value)` rows. The
  first rows are in the cell; the rest are malloc'd.
- A Hash keeps its entries in insertion order, and adds an
  open-addressed index when it holds more than eight.

## Cell sizes

The heap has cells of 32, 64, 128 and 256 bytes. Each size has its own
arenas of 8,192 cells, aligned to 4 MiB. An allocation takes the
smallest size that holds the object and its payload.

| In a cell of | A String holds | An Array holds |
|---|---|---|
| 64 bytes | 23 bytes | 2 elements |
| 128 bytes | 87 bytes | 10 elements |
| 256 bytes | 215 bytes | 26 elements |

## The frame record

Every compiled Ruby function keeps one record in its machine frame:

```ruby
Machine.struct :Frame, prev: Ptr, meta: Ptr, line: Word, self: Value, cref: Value, blk: Value,
               entry: Ptr, defined: Value, serial: Word, nvalues: Word, svars: Value
```

`nvalues` Value slots follow the header: locals, the staging slots of
sends, and the slots of the prologue. The task's `top` points at the
newest record, and `prev` links each record to its caller's.

| Field | Holds |
|---|---|
| `meta` | the `FrameMeta`: name, owner, file, kind, parameters |
| `line` | the current line, for backtraces |
| `entry` | the method entry the call came through, or 0 |
| `defined` | the ancestor chain node the method was found on |
| `serial` | 0 until the frame makes a block; then a number that tells this frame from a later one at the same address |
| `svars` | nil, or the pair of `$~` and `$_` once one is written |

## Method entries and call caches

```ruby
Machine.struct :MEntry, mid: Word, fn: Ptr, arity: Word, kind: Word, meta: Ptr, cref: Value,
               vis: Word, orig: Word, from: Value, core: Word, ivar: IvarCache
Machine.struct :CallCache, klass: Value, stamp: Word, entry: Ptr, found: Value, fn: Ptr
```

A compiled method takes `(recv, argc, argv, entry, blk, found)`. A
builtin takes `(recv, argc, argv, cref, blk)`. Each send site owns four
`CallCache` cells.
