# Runtime layouts

This page lists the runtime's main values and objects, as
`lib/zr/runtime/kernel/` declares them. If this page and the declarations are
different, the declarations are correct. To learn how the collector and
dispatch use them, read
[Memory and the collector](../explanation/memory-and-the-collector.md)
and [Method dispatch and unwinding](../explanation/method-dispatch-and-unwinding.md).

## Values

A `Value` is a 64-bit word with CRuby's tagging (`lib/zr/runtime/kernel/value.rb`).

| Value | Encoding |
|---|---|
| `false` | `0x00` |
| `nil` | `0x04` |
| `true` | `0x14` |
| undef | `0x24`: Ruby code never sees it; it means that an unwind is pending |
| Integer (fixnum) | `n << 1 \| 1` |
| Float (flonum) | low bits `10`, CRuby's rotation |
| Symbol (static) | `id << 8 \| 0x0c` |
| any other object | a nonzero, 8-aligned pointer to a cell that starts with `RBasic` |

`nil.object_id` is 4 (as in ruby 4.0), and `1.0.equal?(1.0)` is true, as in CRuby.

## The object header

```ruby
class RBasic < Layout
  attr_accessor :flags #: word
  attr_accessor :klass #: value
end
```

| Bits of `flags` | Meaning |
|---|---|
| 0-4 | the type (`T_MASK = 31`) |
| 5 | `FL_ALLOCATED` |
| 10 | `FL_EXIVAR` |
| 11 | `FL_FREEZE` |
| 13 | `FL_SINGLETON` |
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
class RString < Layout
  attr_reader :basic #: RBasic
  attr_accessor :len #: word
  attr_accessor :ptr #: ptr
  attr_accessor :capa #: word
end

class RArray < Layout
  attr_reader :basic #: RBasic
  attr_accessor :len #: word
  attr_accessor :capa #: word
  attr_accessor :ptr #: ptr
  attr_accessor :base #: ptr
end

class RObject < Layout
  attr_reader :basic #: RBasic
  attr_reader :iv #: IvTab
end

class RProc < Layout
  attr_reader :basic #: RBasic
  attr_accessor :fn #: ptr
  attr_accessor :meta #: ptr
  attr_accessor :env #: value
  attr_accessor :self #: value
  attr_accessor :cref #: value
  attr_accessor :blk #: value
  attr_accessor :home #: ptr
  attr_accessor :serial #: word
  attr_accessor :site #: word
  attr_accessor :ret_home #: ptr
  attr_accessor :ret_serial #: word
  attr_accessor :spread #: word
  attr_accessor :lambda #: word
  attr_accessor :passed #: word
end

class REnv < Layout
  attr_reader :basic #: RBasic
  attr_accessor :parent #: value
  attr_accessor :slots #: ptr
  attr_accessor :nslots #: word
  attr_accessor :names #: ptr
  attr_accessor :cell #: value
  attr_accessor :home #: ptr
end
```

- A String's bytes and an Array's elements stay in the object's cell
  while they fit, and move to a malloc block when they grow. `ptr`
  points to them in both cases.
- An object's instance variables are a table of `(id, value)` entries.
  The first entries are in the cell; the others are in a malloc block.
- A Hash keeps its entries in insertion order, and adds an
  open-addressed index when it has more than eight.

## Cell sizes

The heap has cells of 32, 64, 128 and 256 bytes. Each size has its own
arenas of 8,192 cells, aligned to 4 MiB. An allocation uses the
smallest size that contains the object and its contents.

| In a cell of | A String contains | An Array contains |
|---|---|---|
| 64 bytes | 23 bytes | 2 elements |
| 128 bytes | 87 bytes | 10 elements |
| 256 bytes | 215 bytes | 26 elements |

## The frame record

Every compiled Ruby function keeps one record in its machine frame:

```ruby
class Frame < Layout
  attr_accessor :prev #: ptr
  attr_accessor :meta #: ptr
  attr_accessor :line #: word
  attr_accessor :self #: value
  attr_accessor :cref #: value
  attr_accessor :blk #: value
  attr_accessor :entry #: ptr
  attr_accessor :defined #: value
  attr_accessor :serial #: word
  attr_accessor :nvalues #: word
  attr_accessor :svars #: value
end
```

`nvalues` Value slots follow the header: locals, the staging slots of
sends, and the slots of the prologue. The task's `top` points at the
newest record, and `prev` links each record to its caller's.

| Field | Contains |
|---|---|
| `meta` | the `FrameMeta`: name, owner, file, kind, parameters |
| `line` | the current line, for backtraces |
| `entry` | the method entry the call came through, or 0 |
| `defined` | the ancestor chain node the method was found on |
| `serial` | 0 until the frame makes a block; then a number that makes this frame different from a later frame at the same address |
| `svars` | nil, or the pair of `$~` and `$_` once one is written |

## Method entries and inline caches

```ruby
class MEntry < Layout
  attr_accessor :mid #: word
  attr_accessor :fn #: ptr
  attr_accessor :arity #: word
  attr_accessor :kind #: word
  attr_accessor :meta #: ptr
  attr_accessor :cref #: value
  attr_accessor :vis #: word
  attr_accessor :orig #: word
  attr_accessor :from #: value
  attr_accessor :core #: word
  attr_reader :ivar #: IvarCache
  attr_accessor :cover #: word
  attr_accessor :direct #: ptr
  attr_accessor :concealed #: word
end

class CallCache < Layout
  attr_accessor :klass #: value
  attr_accessor :stamp #: word
  attr_accessor :entry #: ptr
  attr_accessor :found #: value
  attr_accessor :fn #: ptr
  attr_accessor :shape #: word
  attr_accessor :direct #: ptr
end
```

A compiled method takes `(recv, argc, argv, entry, blk, found)`. A
builtin takes `(recv, argc, argv, cref, blk)`. Each send site owns four
`CallCache` entries: its inline cache.
