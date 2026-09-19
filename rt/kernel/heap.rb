# The heap: cells of four sizes (32, 64, 128 and 256 bytes) from
# arenas through a free list per size; a precise mark-sweep collector
# rooted in the task's frame records and the globals. A freed cell is
# poisoned and loses FL_ALLOCATED, and marking aborts on a reference
# to one: a live object pointing at a freed cell is a root the
# discipline missed. Under ZR_GC_STRESS every allocation collects
# first, and each free list starts just past the last cell handed out,
# so a stale pointer meets the poison, not a new object.
#
# An arena is ARENA_CELLS cells of one size after a head that names it,
# aligned to ARENA_BYTES, so a cell's arena is its address with the low
# bits cleared; the arena's exivar slots follow its cells, and its mark
# bitmap follows those. A mark is a bit in that map and never a write
# into the cell, so a collection leaves the pages a fork shares
# untouched, and a sweep reads one word to step over sixty-four live
# cells. Every size
# has the same count, so the heap a program starts with, and what a
# collection sweeps of it, is the 32,768 cells of four arenas: what the
# one 128-byte arena of the heap before cost. An arena a sweep finds
# with no live cell is reserved: its cells stay linked among themselves,
# no sweep reads it again, and an allocation takes it when its size's
# free list runs out. The collector runs when both are empty, and grows
# each size to twice what the sweep found live of it. The arenas are
# listed in a malloc'd table that doubles when full, so the heap has no
# ceiling but the machine's.
ARENA_BYTES = 4194304
ARENA_HEAD = 256
ARENA_CELLS = 8192
ARENA_TABLE = 64
# The bytes of an arena's mark bitmap, one bit a cell, and the word of
# that map whose every cell is live.
MARK_BYTES = ARENA_CELLS >> 3
ALL_MARKED = 0 - 1
CELL_MIN = 32
CELL_MAX = 256
SIZE_CLASSES = 4
POISON = 57005 << 8

# What an arena says of itself: its cell size, that size as a shift,
# how many cells follow the head, and its size class's index.
# A reserved arena is one whose cells are all free and linked among
# themselves from `chain`, on its size class's list of them through
# `next`; no sweep reads it.
Machine.struct :ArenaHead, cell: Word, shift: Word, ncells: Word, index: Word, reserved: Word, remembered: Word, chain: Ptr, next: Ptr

# One cell size: its free list, the last cell handed out (0 before the
# first), the cells the last sweep found free, its arena count, its
# reserved arenas, and the objects it has handed out.
Machine.struct :SizeClass, free: Ptr, last: Ptr, freed: Word, arenas: Word, reserve: Ptr, allocated: Word

# Heap state: collections, stress flag, the arena count,
# the time collecting, the arena table and its capacity, the malloc'd
# payload bytes held (zr_xmalloc, zr_xfree), the count of them that
# runs the collector, and whether an allocation takes the slow path
# (zr_heap_slow_update).
Machine.struct :Heap, collections: Word, stress: Word, disabled: Word, arenas: Word, nanoseconds: Word, table: Ptr, capacity: Word, malloced: Word, malloc_limit: Word, slow: Word, minors: Word, verify: Word, verifying: Word, live: Word, old_limit: Word

# The payload a collection lets the heap take on before the next one
# runs on that account, and the bounds on that increment. CRuby holds
# the same counter between GC_MALLOC_LIMIT_MIN and GC_MALLOC_LIMIT_MAX,
# 16 and 32 megabytes, and grows it by 1.4 of what was found live;
# these are four times its bounds, since a collection here marks
# everything where CRuby's marks the young.
#
# The rule these replace was a flat `malloced * 2` with no ceiling at
# all, so a build holding four gigabytes of payload would not collect on
# that account until it held eight.
MALLOC_LIMIT = 67108864
MALLOC_LIMIT_MAX = 134217728
MALLOC_GROWTH = 140

# The free cells a size class should hold once a collection has swept
# it, as hundredths of its capacity, and the most one collection may
# grow it by. The shape is CRuby's, whose
# `heap_allocatable_slots_expand` grows a heap only where the sweep
# left it under the floor free, grows it to the goal, and never by more
# than the factor in one step (0.20, 0.40 and 1.8 in
# gc/default/default.c). The goal here is half and not two fifths,
# since every collection is major: a class this one grows is left
# holding twice its live set, as the rule before this held every class.
FREE_FLOOR = 20
FREE_GOAL = 50
GROWTH = 180

# What the old generation may grow to before a major collection runs,
# as a multiple of what the last major found live, and the least that
# multiple may stand for. A minor frees what died young and steps over
# everything older, so nothing else frees an old graph that has gone
# dead, nor the floating garbage a minor leaves behind; this is what
# bounds both. It is CRuby's `old_objects_limit`, which is likewise
# twice what the last major counted.
OLD_LIMIT_FACTOR = 2
OLD_LIMIT_MIN = 16777216

# A backstop under that: minor collections that run before a major one
# whatever the old set has done. A program whose old generation never
# grows still wants its weak references and its finalizers looked at.
MAJOR_EVERY = 16

# The share of the machine's memory the cells may reach before growth
# falls back to the floor, in hundredths. Past it a collection costs
# less than a page-in does, so the collector runs more often rather than
# asking for memory the machine has to find somewhere: six compiler
# workers that each grew without a bound took a sixteen-gigabyte machine
# into 16.4 GB of swap, and a run that swaps does not fail -- it takes
# ten times as long.
HEAP_SHARE = 50

sig [] => Ptr
machine def zr_heap
  Machine.static(:heap, Heap.size)
end

sig [Word] => Ptr
machine def zr_arena_at(i)
  Machine.ptr(Machine.load64(Heap.table(zr_heap()) + (i * 8), 0))
end

# Room in the arena table for one more arena.
sig [] => Void
machine def zr_arena_table_grow
  h = zr_heap()
  n = Heap.arenas(h)
  if n < Heap.capacity(h)
    return
  end
  capacity = n == 0 ? ARENA_TABLE : n * 2
  table = zr_xmalloc(capacity * 8)
  if n != 0
    zr_memcpy(table, Heap.table(h), n * 8)
    zr_xfree(Heap.table(h))
  end
  Heap.set_table(h, table)
  Heap.set_capacity(h, capacity)
end

sig [Value] => Ptr
machine def zr_arena_of(v)
  Machine.ptr(Machine.word(v) & (0 - ARENA_BYTES))
end

# The size class `c` (0 to 3): cells of CELL_MIN << c bytes.
sig [Word] => Ptr
machine def zr_size_class(c)
  Machine.static(:size_classes, SizeClass.size * SIZE_CLASSES) + (c * SizeClass.size)
end

# The size class whose cells hold `bytes`, which is CELL_MAX at most:
# each constructor asks for its struct's size, or clamps a payload to
# the largest cell and mallocs the rest. One expression, so the
# allocation inlines it.
sig [Word] => Word
machine def zr_size_class_for(bytes)
  bytes <= CELL_MIN ? 0 : (bytes <= CELL_MIN * 2 ? 1 : (bytes <= CELL_MIN * 4 ? 2 : 3))
end

# The bytes of `v`'s cell: the size its arena holds.
sig [Value] => Word
machine def zr_cell_bytes(v)
  ArenaHead.cell(zr_arena_of(v))
end

# Arena `a`'s mark bitmap, between its head and its cells: a fixed
# offset, so reading a cell's bit asks the head for nothing but the
# shift that turns its address into an index.
sig [Ptr] => Ptr
machine def zr_arena_marks(a)
  a + ARENA_HEAD
end

# Arena `a`'s age bitmap, beside its marks: the marks the last
# collection finished with, which is to say the cells that survived it.
# Those are the old objects, and this is the map the write barrier and a
# minor collection read. The marks themselves go back to zero at the end
# of every collection, so nothing outside one is marked and ObjectSpace's
# walk of what an object refers to (rt/kernel/objspace.rb) still reads
# the mark bitmap as its own scratch.
sig [Ptr] => Ptr
machine def zr_arena_ages(a)
  a + ARENA_HEAD + MARK_BYTES
end

# Arena `a`'s remembered bitmap, beside its ages. A cell's bit is set
# where the cell is old and has come to hold a young object, so a minor
# collection has to read it again although it would stop at it.
sig [Ptr] => Ptr
machine def zr_arena_remembered(a)
  a + ARENA_HEAD + (MARK_BYTES * 2)
end

# The first cell of arena `a`, after its head and its three bitmaps.
sig [Ptr] => Ptr
machine def zr_arena_first(a)
  a + ARENA_HEAD + (MARK_BYTES * 3)
end

# The exivar slots of arena `a`, one a cell, after its cells.
sig [Ptr] => Ptr
machine def zr_arena_exivars(a)
  zr_arena_first(a) + (ArenaHead.ncells(a) * ArenaHead.cell(a))
end

# The word of each of `a`'s bitmaps that holds cell `i`'s bit, and that
# bit. The three maps have the same shape, so one bit serves all three.
sig [Ptr, Word] => Ptr
machine def zr_marks_word(a, i)
  zr_arena_marks(a) + ((i >> 6) * 8)
end

sig [Ptr, Word] => Ptr
machine def zr_ages_word(a, i)
  zr_arena_ages(a) + ((i >> 6) * 8)
end

sig [Ptr, Word] => Ptr
machine def zr_remembered_word(a, i)
  zr_arena_remembered(a) + ((i >> 6) * 8)
end

sig [Word] => Word
machine def zr_marks_bit(i)
  1 << (i & 63)
end

# The index of cell `v` among arena `a`'s.
sig [Ptr, Value] => Word
machine def zr_cell_index_in(a, v)
  (Machine.word(v) - zr_arena_first(a)) >> ArenaHead.shift(a)
end

# The index of `v`'s cell among its arena's.
sig [Value] => Word
machine def zr_cell_index(v)
  zr_cell_index_in(zr_arena_of(v), v)
end

# Whether `v` is marked, and the two writes to its bit. A Proc or an Env
# on the machine stack is in no arena and has no bit of its own, so
# every caller here tests FL_STACK before it asks.
sig [Value] => Bool
machine def zr_marked_p(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  (Machine.load64(zr_marks_word(a, i), 0) & zr_marks_bit(i)) != 0
end

sig [Value] => Void
machine def zr_mark_set(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  at = zr_marks_word(a, i)
  Machine.store64(at, 0, Machine.load64(at, 0) | zr_marks_bit(i))
end

sig [Value] => Void
machine def zr_mark_unset(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  at = zr_marks_word(a, i)
  Machine.store64(at, 0, Machine.load64(at, 0) & (0 - 1 - zr_marks_bit(i)))
end

# Whether `v` survived a collection, which is what "old" means here. An
# immediate has no cell, and a Proc or an Env on the machine stack is in
# no arena, so neither has a bit to read.
sig [Value] => Bool
machine def zr_aged_p(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  (Machine.load64(zr_ages_word(a, i), 0) & zr_marks_bit(i)) != 0
end

sig [Value] => Bool
machine def zr_old_p(v)
  !zr_special_p(v) && (RBasic.flags(v) & FL_STACK) == 0 && zr_aged_p(v)
end
Machine.inline :zr_old_p

# `v`'s bit set in its arena's remembered map, and the arena flagged, so
# a minor collection reads the map of that arena alone. The bits are a
# map and not a list: there is nothing to allocate, nothing to
# de-duplicate and nothing to overflow, which is what
# `rgengc_rememberset_mark` gets out of CRuby's `remembered_bits`.
sig [Value] => Void
machine def zr_remember(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  at = zr_remembered_word(a, i)
  Machine.store64(at, 0, Machine.load64(at, 0) | zr_marks_bit(i))
  ArenaHead.set_remembered(a, 1)
end

# `owner` has come to hold `value`.
#
# A minor collection starts from the roots and from what is remembered
# and stops at every object already marked, so an old object that comes
# to refer to a young one has to be written down or the young one is
# swept from under it. Nothing is owed where the owner is young -- a
# minor collection reaches that one from the roots anyway -- nor where
# the value is an immediate, or is old itself.
#
# CRuby needs this same barrier and cannot check it: every C function
# that stores a VALUE into an object must call `RB_OBJ_WRITE` by hand,
# which is why it carries wb-unprotected objects that are never promoted
# and a whole second collector (gc/wbcheck) whose only job is to find
# the calls that are missing. Here the compiler emits the store, so it
# emits the barrier with it: `Machine::Lower#field` writes one after
# every store into a Value field of a struct that begins with an
# RBasic, which is to say into a cell.
sig [Value, Value] => Void
machine def zr_write_barrier(owner, value)
  if zr_old_p(owner) && !zr_old_p(value)
    zr_remember(owner)
  end
end
Machine.inline :zr_write_barrier

# `owner` remembered where it is old, whatever it has come to hold: what
# a bulk write into a buffer it keeps owes the collector, where naming
# each value one at a time would cost more than reading the cell again
# will.
sig [Value] => Void
machine def zr_write_barrier_all(owner)
  if zr_old_p(owner)
    zr_remember(owner)
  end
end
Machine.inline :zr_write_barrier_all

# Every arena's bitmap cleared, which a collection does once it has
# swept: no cell is marked outside a collection, and ObjectSpace's walk
# of what one object refers to (rt/kernel/objspace.rb) marks and unmarks
# on that footing.
sig [] => Void
machine def zr_marks_clear
  n = Heap.arenas(zr_heap())
  i = 0
  while i < n
    memset(zr_arena_marks(zr_arena_at(i)), Machine.i32(0), MARK_BYTES)
    i += 1
  end
end

# What a collection finished marking kept as the ages, and the
# remembered bits emptied: the cells that survived this collection are
# the old ones from here on, and what the barrier wrote down has been
# read.
sig [] => Void
machine def zr_ages_keep
  n = Heap.arenas(zr_heap())
  i = 0
  while i < n
    a = zr_arena_at(i)
    zr_memcpy(zr_arena_ages(a), zr_arena_marks(a), MARK_BYTES)
    memset(zr_arena_remembered(a), Machine.i32(0), MARK_BYTES)
    ArenaHead.set_remembered(a, 0)
    i += 1
  end
end

# The bytes an arena of size class `c` takes: its head, its three
# bitmaps, its cells and the exivar slot each of them carries.
sig [Word] => Word
machine def zr_arena_bytes(c)
  ARENA_HEAD + (MARK_BYTES * 3) + (ARENA_CELLS * ((CELL_MIN << c) + 8))
end

# The bytes of live cells the heap holds, which the sweep has counted.
sig [] => Word
machine def zr_live_bytes
  bytes = 0
  c = 0
  while c < SIZE_CLASSES
    sc = zr_size_class(c)
    bytes += ((SizeClass.arenas(sc) * ARENA_CELLS) - SizeClass.freed(sc)) * (CELL_MIN << c)
    c += 1
  end
  bytes
end

# The bytes of arenas the heap holds, live cells and free alike.
sig [] => Word
machine def zr_heap_bytes
  bytes = 0
  c = 0
  while c < SIZE_CLASSES
    bytes += SizeClass.arenas(zr_size_class(c)) * zr_arena_bytes(c)
    c += 1
  end
  bytes
end

# What this machine has to hold a heap in, asked of the host once. A
# machine that will not say is treated as one of four gigabytes.
sig [] => Word
machine def zr_machine_bytes
  at = Machine.static(:machine_bytes, 8)
  known = Machine.load64(at, 0)
  if known != 0
    return known
  end
  pages = sysconf(Machine.i32(SC_PHYS_PAGES))
  size = sysconf(Machine.i32(SC_PAGESIZE))
  bytes = pages == 0 - 1 || size == 0 - 1 ? 4294967296 : pages * size
  Machine.store64(at, 0, bytes)
  bytes
end

# A new arena of size class `c`, reserved: its head written, its
# poisoned cells linked in address order, its exivar slots and its mark
# bitmap clear.
sig [Word] => Void
machine def zr_arena_add(c)
  h = zr_heap()
  zr_arena_table_grow()
  n = Heap.arenas(h)
  bytes = CELL_MIN << c
  slot = Machine.slot(8)
  if posix_memalign(slot, ARENA_BYTES, zr_arena_bytes(c)) != Machine.i32(0)
    zr_memory_exhausted()
  end
  a = Machine.ptr(Machine.load64(slot, 0))
  ArenaHead.set_cell(a, bytes)
  ArenaHead.set_shift(a, 5 + c)
  ArenaHead.set_ncells(a, ARENA_CELLS)
  ArenaHead.set_index(a, c)
  Machine.store64(Heap.table(h) + (n * 8), 0, Machine.word(a))
  Heap.set_arenas(h, n + 1)
  sc = zr_size_class(c)
  SizeClass.set_arenas(sc, SizeClass.arenas(sc) + 1)
  first = zr_arena_first(a)
  slots = zr_arena_exivars(a)
  head = 0
  i = ARENA_CELLS - 1
  while i >= 0
    cell = first + (i * bytes)
    Machine.store64(cell, 0, POISON)
    Machine.store64(cell, 8, head)
    Machine.store64(slots + (i * 8), 0, 0)
    head = cell
    i -= 1
  end
  memset(zr_arena_marks(a), Machine.i32(0), MARK_BYTES * 3)
  zr_arena_reserve(a, head)
end

# Arena `a`, every cell free and linked from `chain`, put by for its
# size class.
sig [Ptr, Ptr] => Void
machine def zr_arena_reserve(a, chain)
  sc = zr_size_class(ArenaHead.index(a))
  ArenaHead.set_reserved(a, 1)
  ArenaHead.set_chain(a, chain)
  ArenaHead.set_next(a, SizeClass.reserve(sc))
  SizeClass.set_reserve(sc, a)
end

# The next reserved arena of size class `sc` becomes its free list, when
# the list is empty and there is one.
sig [Ptr] => Void
machine def zr_arena_unreserve(sc)
  a = SizeClass.reserve(sc)
  if a == 0 || SizeClass.free(sc) != 0
    return
  end
  SizeClass.set_reserve(sc, ArenaHead.next(a))
  ArenaHead.set_reserved(a, 0)
  SizeClass.set_free(sc, ArenaHead.chain(a))
end

# The frame chain the collector walks: a record is a Frame followed by
# `nvalues` Values.
# `entry` is the method entry a method frame was called through, whose
# `mid` is the name it was called by, an alias's own; 0 for a frame that
# is no method's. `defined` is the class or proxy the method was found
# in, which `super` continues from (a module included twice has two
# proxies). `serial` tells one frame at an address from the next: 0
# until something needs it (`zr_frame_serial`). `svars` is nil until
# `$~` or `$_` is written under the frame, then a two-element Array of
# them (`zr_svars`).
Machine.struct :Frame, prev: Ptr, meta: Ptr, line: Word, self: Value, cref: Value, blk: Value, entry: Ptr, defined: Value, serial: Word, nvalues: Word, svars: Value
Machine.struct :Task, top: Ptr, serial: Word, pending: Value, errinfo: Value, pending_kind: Word, pending_home: Ptr, pending_site: Word, kw: Word, stack_limit: Ptr, guards: Value, catches: Value, throw_tag: Value, missing: Word, found: Value, refine: Value, ractor: Word

# The runtime's own roots: the core classes and the main object.
G_BASIC_OBJECT = 0
G_OBJECT = 1
G_MODULE = 2
G_CLASS = 3
G_KERNEL = 4
G_INTEGER = 5
G_STRING = 6
G_SYMBOL = 7
G_NIL = 8
G_TRUE = 9
G_FALSE = 10
G_MAIN = 11
G_NUMERIC = 13
G_COUNT = 63

sig [] => Ptr
machine def zr_globals
  Machine.static(:globals, G_COUNT * 8)
end

sig [Word] => Value
machine def zr_global(i)
  Machine.value(Machine.load64(zr_globals() + (i * 8), 0))
end

sig [Word, Value] => Void
machine def zr_set_global(i, v)
  Machine.store64(zr_globals() + (i * 8), 0, Machine.word(v))
end

# One reserved arena per size class from the start, and a second of
# 64-byte cells: the boot makes some ten thousand small Strings and
# Arrays, and a program that runs no collection of its own runs none.
sig [] => Void
machine def zr_heap_init
  h = zr_heap()
  Heap.set_malloc_limit(h, MALLOC_LIMIT)
  Heap.set_old_limit(h, OLD_LIMIT_MIN)
  c = 0
  while c < SIZE_CLASSES
    zr_arena_add(c)
    c += 1
  end
  zr_arena_add(1)
  if getenv(Machine.bytes("ZR_GC_STRESS\0")) != 0
    Heap.set_stress(h, 1)
  end
  if getenv(Machine.bytes("ZR_GC_VERIFY\0")) != 0
    Heap.set_verify(h, 1)
  end
  zr_heap_slow_update()
end

# The object whose children are being marked, so the abort below can
# name what pointed at a freed cell.
sig [] => Ptr
machine def zr_marking
  Machine.static(:marking, 8)
end

# The cells marked but not yet traced: a growable stack, so a long
# chain of objects costs no machine stack.
Machine.struct :MarkStack, ptr: Ptr, len: Word, capa: Word

sig [] => Ptr
machine def zr_mark_stack
  Machine.static(:mark_stack, MarkStack.size)
end

# Mark `v` and queue it for tracing. Most references a collection reads
# are immediates or cells it has marked already, so the test for those
# is small enough to stand in each place a reference is read, and only
# a cell still to mark costs a call. A Proc or an Env on the machine
# stack lives as long as the frame that holds it and has no bit in any
# arena, so the flag it carries takes it out of the collection here.
sig [Value] => Void
machine def zr_mark(v)
  unless zr_special_p(v) || (RBasic.flags(v) & FL_STACK) != 0 || zr_marked_p(v)
    zr_mark_cell(v)
  end
end

# Nonzero while ObjectSpace reads what one object refers to, which
# needs every cell it marks on the queue.
sig [] => Ptr
machine def zr_mark_every
  Machine.static(:mark_every, 8)
end

# A freed cell here is a root the discipline missed, and the abort names
# what pointed at it.
sig [Value] => Void
machine def zr_mark_cell(v)
  flags = RBasic.flags(v)
  if (flags & FL_ALLOCATED) == 0
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("a live object points at a freed cell: from a cell of type "), 58)
    parent = Machine.value(Machine.load64(zr_marking(), 0))
    if parent == QNIL
      zr_buf_push(b, Machine.bytes("root"), 4)
    elsif zr_fixnum_p(parent)
      zr_buf_push(b, Machine.bytes("root "), 5)
      zr_buf_long(b, zr_fix2long(parent))
    else
      zr_buf_long(b, RBasic.flags(parent) & T_MASK)
    end
    zr_buf_byte(b, 10)
    zr_bug(Buf.ptr(b), Buf.len(b))
  end
  if zr_marked_p(v)
    return
  end
  zr_mark_set(v)
  if Heap.verifying(zr_heap()) != 0
    zr_verify_reached(v)
  end
  # A String or a Float holds no Value: in a collection its class is
  # marked here, and the queue never sees it. ObjectSpace's walk of one
  # object's references reads them back off the queue, so there every
  # cell goes on it.
  t = flags & T_MASK
  if (t == T_STRING || t == T_FLOAT) && (flags & FL_EXIVAR) == 0 && Machine.load64(zr_mark_every(), 0) == 0
    zr_mark(RBasic.klass(v))
    return
  end
  s = zr_mark_stack()
  n = MarkStack.len(s)
  if n == MarkStack.capa(s)
    capa = n == 0 ? 1024 : n * 2
    grown = zr_xmalloc(capa * 8)
    if n > 0
      zr_memcpy(grown, MarkStack.ptr(s), n * 8)
      zr_xfree(MarkStack.ptr(s))
    end
    MarkStack.set_ptr(s, grown)
    MarkStack.set_capa(s, capa)
  end
  Machine.store64(MarkStack.ptr(s) + (n * 8), 0, Machine.word(v))
  MarkStack.set_len(s, n + 1)
end

# Trace every queued cell: its class, its children, its exivars.
sig [] => Void
machine def zr_mark_drain
  s = zr_mark_stack()
  while MarkStack.len(s) > 0
    n = MarkStack.len(s) - 1
    MarkStack.set_len(s, n)
    v = Machine.value(Machine.load64(MarkStack.ptr(s) + (n * 8), 0))
    Machine.store64(zr_marking(), 0, Machine.word(v))
    zr_mark(RBasic.klass(v))
    zr_mark_children(v)
    if (RBasic.flags(v) & FL_EXIVAR) != 0
      zr_mark_ivtab(zr_exivar_tab(v))
    end
  end
end

# The ivar tables of objects whose kind has none of its own: one slot
# per cell after its arena's cells, holding a table or 0.
sig [Value] => Ptr
machine def zr_exivar_slot(v)
  zr_arena_exivars(zr_arena_of(v)) + (zr_cell_index(v) * 8)
end

sig [Value] => Ptr
machine def zr_exivar_tab(v)
  Machine.ptr(Machine.load64(zr_exivar_slot(v), 0))
end

# The table for `v`, made on first use.
sig [Value] => Ptr
machine def zr_exivar_tab_for_write(v)
  t = zr_exivar_tab(v)
  if t == 0
    t = zr_xmalloc(IvTab.size)
    zr_ivtab_init(t)
    Machine.store64(zr_exivar_slot(v), 0, Machine.word(t))
    RBasic.set_flags(v, RBasic.flags(v) | FL_EXIVAR)
  end
  t
end

sig [Value] => Void
machine def zr_exivar_free(v)
  t = zr_exivar_tab(v)
  zr_release_ivtab(t)
  zr_xfree(t)
  Machine.store64(zr_exivar_slot(v), 0, 0)
end

# Global variables: one table of (id, value) rows.
sig [] => Ptr
machine def zr_gvars
  Machine.static(:gvars, IvTab.size)
end

# `alias $new $old`: the alias names the same row; the table maps an
# alias to the name it stands for, already resolved.
sig [] => Ptr
machine def zr_gvar_aliases
  Machine.static(:gvar_aliases, IvTab.size)
end

sig [Word] => Word
machine def zr_gvar_resolve(id)
  if IvTab.len(zr_gvar_aliases()) == 0
    return id
  end
  target = zr_ivtab_get(zr_gvar_aliases(), id)
  target == QUNDEF ? id : zr_fix2long(target)
end

sig [Word, Word] => Void
machine def zr_gvar_alias(new_id, old_id)
  zr_ivtab_set(zr_gvar_aliases(), new_id, zr_fix(zr_gvar_resolve(old_id)))
end

sig [Word] => Value
machine def zr_gvar_get(id)
  b = zr_box_current()
  if b != QNIL
    v = zr_hash_lookup(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id)))
    return v == QUNDEF ? Machine.value(QNIL) : v
  end
  v = zr_ivtab_get(zr_gvars(), zr_gvar_resolve(id))
  if v == QUNDEF
    return Machine.value(QNIL)
  end
  v
end

sig [Word] => Value
machine def zr_gvar_defined(id)
  b = zr_box_current()
  if b != QNIL
    return zr_bool(zr_hash_lookup(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id))) != QUNDEF)
  end
  zr_bool(zr_ivtab_row(zr_gvars(), zr_gvar_resolve(id)) != 0)
end

sig [Word, Value] => Value
machine def zr_gvar_set(id, v)
  b = zr_box_current()
  if b != QNIL
    zr_hash_store(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id)), v)
    return v
  end
  zr_ivtab_set(zr_gvars(), zr_gvar_resolve(id), v)
  v
end

# `$name = v` as Ruby writes it. A name `alias` made stands for a global
# ruby may hook, which checks the value.
sig [Word, Value] => Value
machine def zr_gvar_assign(id, v)
  target = zr_gvar_resolve(id)
  if target != id
    return zr_gvar_hooked(id, target, v)
  end
  zr_gvar_store(id, v)
end

# `$name = v` for a global ruby hooks: Kernel's hook checks the value,
# or refuses a read-only global under the name the program wrote, and
# answers what to store.
sig [Word, Word, Value] => Value
machine def zr_gvar_hooked(shown, id, v)
  argv = Machine.slot(24)
  Machine.store64(argv, 0, Machine.word(zr_sym(shown)))
  Machine.store64(argv, 8, Machine.word(zr_sym(id)))
  Machine.store64(argv, 16, Machine.word(v))
  stored = zr_send(zr_global(G_KERNEL), Machine.id(:hooked_global), 3, argv)
  return stored if stored == QUNDEF
  zr_gvar_store(id, stored)
  v
end

# The value stored, then the commands trace_var put on the global run
# with it. QUNDEF when one raised.
sig [Word, Value] => Value
machine def zr_gvar_store(id, v)
  zr_gvar_set(id, v)
  if Machine.load64(Machine.static(:gvar_traced, 8), 0) == 0
    return v
  end
  argv = Machine.slot(16)
  Machine.store64(argv, 0, Machine.word(zr_sym(zr_gvar_resolve(id))))
  Machine.store64(argv, 8, Machine.word(v))
  if zr_send(zr_global(G_KERNEL), Machine.id(:traced_assign), 2, argv) == QUNDEF
    return Machine.value(QUNDEF)
  end
  v
end

# The first trace_var: from now on an assignment asks for commands.
sig [] => Value
machine def zr_gvar_traced
  Machine.store64(Machine.static(:gvar_traced, 8), 0, 1)
  Machine.value(QNIL)
end

# The name `alias $new $old` makes `name` stand for, or `name` itself.
sig [Value] => Value
machine def zr_gvar_resolve_m(name)
  zr_sym(zr_gvar_resolve(zr_sym2id(name)))
end

# Whether the global `name` has a row: it was assigned.
sig [Value] => Value
machine def zr_gvar_defined_m(name)
  zr_gvar_defined(zr_sym2id(name))
end

# `$name` and `$name = v` for the walking eval road, which names a
# global by Symbol where compiled code names it by id. A write goes
# through the hooked form, since the road is the program's own code
# running a string the program wrote: `$stdout = 1` must raise there
# as it does anywhere else.
sig [Value] => Value
machine def zr_gvar_get_m(name)
  zr_gvar_get(zr_sym2id(name))
end

sig [Value, Value, Value] => Value
machine def zr_gvar_hooked_m(shown, name, v)
  zr_gvar_hooked(zr_sym2id(shown), zr_sym2id(name), v)
end

sig [Value, Value] => Value
machine def zr_gvar_assign_m(name, v)
  zr_gvar_assign(zr_sym2id(name), v)
end

sig [Value, Value] => Value
machine def zr_gvar_alias_m(new_name, old_name)
  zr_gvar_alias(zr_sym2id(new_name), zr_sym2id(old_name))
  Machine.value(QNIL)
end

sig [] => Void
machine def zr_mark_roots
  i = 0
  while i < G_COUNT
    Machine.store64(zr_marking(), 0, Machine.word(zr_fix(1000 + i)))
    zr_mark(zr_global(i))
    i += 1
  end
  Machine.store64(zr_marking(), 0, Machine.word(zr_fix(2)))
  zr_mark_ivtab(zr_gvars())
  zr_mark(Machine.value(Machine.load64(Machine.static(:current_fiber, 8), 0)))
  zr_mark(Machine.value(Machine.load64(Machine.static(:root_fiber, 8), 0)))
  zr_mark_task(zr_task())
  Machine.store64(zr_marking(), 0, Machine.word(zr_fix(3)))
  zr_mark_kernel_roots()
  zr_mark_finalizer_queue()
end

# A task's roots: its slots and its frame chain.
sig [Ptr] => Void
machine def zr_mark_task(t)
  zr_mark(Task.pending(t))
  zr_mark(Task.errinfo(t))
  zr_mark(Task.guards(t))
  zr_mark(Task.catches(t))
  zr_mark(Task.throw_tag(t))
  zr_mark(Task.found(t))
  zr_mark(Task.refine(t))
  rec = Task.top(t)
  while rec != 0
    Machine.store64(zr_marking(), 0, Machine.word(zr_fix(4)))
    zr_mark(Frame.self(rec))
    zr_mark(Frame.cref(rec))
    zr_mark(Frame.blk(rec))
    zr_mark(Frame.svars(rec))
    zr_mark(Frame.defined(rec))
    n = Frame.nvalues(rec)
    i = 0
    while i < n
      Machine.store64(zr_marking(), 0, Machine.word(zr_fix(100 + i)))
      zr_mark(Machine.value(Machine.load64(rec + Frame.size + (i * 8), 0)))
      i += 1
    end
    rec = Frame.prev(rec)
  end
end

# Free an unmarked cell of `bytes` that was live: release what it owns,
# and poison it.
sig [Ptr, Word] => Void
machine def zr_free_cell(cell, bytes)
  flags = Machine.load64(cell, 0)
  if (flags & FL_ALLOCATED) != 0
    zr_release(Machine.value(cell))
    if (flags & FL_EXIVAR) != 0
      zr_exivar_free(Machine.value(cell))
    end
  end
  if AllocTrace.used(zr_alloc_trace()) != 0
    zr_alloc_trace_forget(cell)
  end
  Machine.store64(cell, 0, POISON)
  # The header's poison is what mark checks; the payload's is only there
  # to make a stale read loud, which stress mode is for.
  if Heap.stress(zr_heap()) != 0
    zr_poison_payload(cell, bytes)
  end
end

# Every payload word of a cell of `bytes` made 0xDEAD: a Value that is
# no fixnum, no nil and no cell, so a read of it stops the program at
# once.
sig [Ptr, Word] => Void
machine def zr_poison_payload(cell, bytes)
  j = RBasic.size
  while j < bytes
    Machine.store64(cell + j, 0, 57005)
    j += 8
  end
end

# The cells of an arena from `stop` down to `start`, pushed in reverse
# so the list pops in address order. A live cell is never read: the
# sweep takes a word of the mark bitmap and steps over the sixty-four
# cells it covers wherever every one of them is marked, which in a heap
# as full as a compiler's is most of them. A cell freed before keeps its
# poison and takes only the link, so the loop calls out for a cell that
# dies in this collection alone. A `whole` arena found with no live cell
# is reserved instead: its cells went onto the list as one run, which
# comes off again as its chain.
sig [Ptr, Word, Word, Bool] => Void
machine def zr_sweep_arena(a, start, stop, whole)
  sc = zr_size_class(ArenaHead.index(a))
  bytes = ArenaHead.cell(a)
  first = zr_arena_first(a)
  marks = zr_arena_marks(a)
  before = SizeClass.free(sc)
  free = before
  freed = 0
  i = stop
  while i >= start
    word = Machine.load64(marks + ((i >> 6) * 8), 0)
    if word == ALL_MARKED && (i & 63) == 63 && (i - 63) >= start
      i -= 64
    else
      if (word & zr_marks_bit(i)) == 0
        cell = first + (i * bytes)
        if Machine.load64(cell, 0) != POISON
          zr_free_cell(cell, bytes)
        end
        Machine.store64(cell, 8, free)
        free = cell
        freed += 1
      end
      i -= 1
    end
  end
  if whole && freed == ARENA_CELLS
    Machine.store64(first + (stop * bytes), 8, 0)
    zr_arena_reserve(a, free)
    free = before
  end
  SizeClass.set_free(sc, free)
  SizeClass.set_freed(sc, SizeClass.freed(sc) + freed)
end

# Every arena's cells, a size class at a time, its list starting at the
# cell after the last one handed out: its arena's tail, then the class's
# other arenas, then its arena's head. A reserved arena is all free
# already, and no sweep reads it.
sig [] => Void
machine def zr_sweep
  n = Heap.arenas(zr_heap())
  c = 0
  while c < SIZE_CLASSES
    sc = zr_size_class(c)
    SizeClass.set_free(sc, 0)
    SizeClass.set_freed(sc, 0)
    home = Machine.ptr(0)
    split = 0
    if SizeClass.last(sc) != 0
      last = Machine.value(SizeClass.last(sc))
      home = zr_arena_of(last)
      split = zr_cell_index(last)
      zr_sweep_arena(home, 0, split, false)
    end
    i = n - 1
    while i >= 0
      a = zr_arena_at(i)
      if a != home && ArenaHead.index(a) == c
        if ArenaHead.reserved(a) != 0
          SizeClass.set_freed(sc, SizeClass.freed(sc) + ARENA_CELLS)
        else
          zr_sweep_arena(a, 0, ARENA_CELLS - 1, true)
        end
      end
      i -= 1
    end
    if home != 0
      zr_sweep_arena(home, split + 1, ARENA_CELLS - 1, false)
    end
    c += 1
  end
end

# Collect for an allocation in size class `wanting` (SIZE_CLASSES when
# none asked). A major collection runs where the minors before it have
# had their turn, or where the heap has reached its share of the machine
# and only a major can give any of it back; every other one is minor.
sig [Word] => Void
machine def zr_collect(wanting)
  h = zr_heap()
  major = Heap.live(h) > Heap.old_limit(h) || Heap.minors(h) >= MAJOR_EVERY || zr_heap_pressed()
  zr_collect_kind(wanting, major)
  # A minor that has left the class that ran out still short did not
  # free what the program had finished with: what filled the heap was
  # not the young dead, and only a major collection can give any of it
  # back. CRuby forces one on the same footing
  # (GPR_FLAG_MAJOR_BY_NOFREE), and the alternative is to grow the heap
  # around objects that have been dead for sixteen collections.
  if !major && zr_heap_short(wanting)
    zr_collect_kind(wanting, true)
  end
  zr_heap_grow(wanting)
  zr_malloc_limit_set()
  zr_heap_slow_update()
end

# Whether the cells have reached their share of the machine.
sig [] => Bool
machine def zr_heap_pressed
  zr_heap_bytes() * 100 > zr_machine_bytes() * HEAP_SHARE
end

# Whether the sweep has left size class `c` under its floor of free
# cells. SIZE_CLASSES is no class, which is what a collection nothing
# asked for passes.
sig [Word] => Bool
machine def zr_heap_short(c)
  if c >= SIZE_CLASSES
    return false
  end
  sc = zr_size_class(c)
  SizeClass.freed(sc) * 100 < SizeClass.arenas(sc) * ARENA_CELLS * FREE_FLOOR
end

# A collection of one kind or the other, then the growth the sweep asks
# for.
#
# A **major** one marks from nothing, so it reaches every live object and
# the sweep frees everything else.
#
# A **minor** one starts its marks from the ages -- the marks the last
# collection finished with -- so the trace stops at every object that
# survived it, and reaches only what has been allocated since. The
# remembered arenas make up the difference: an old object that has come
# to hold a young one is read again although the trace would step over
# it. The sweep is the same sweep, and frees exactly the young dead.
#
# What a minor accepts is floating garbage, an old object that died after
# the collection that marked it and waits for the next major, and no
# demotion. Both are the ordinary generational trade.
sig [Word, Bool] => Void
machine def zr_collect_kind(wanting, major)
  h = zr_heap()
  started = zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC)))
  Heap.set_collections(h, Heap.collections(h) + 1)
  Heap.set_minors(h, major ? 0 : Heap.minors(h) + 1)
  Machine.store64(zr_marking(), 0, QNIL)
  unless major
    zr_marks_from_ages()
  end
  zr_mark_roots()
  unless major
    zr_mark_remembered()
  end
  zr_mark_drain()
  zr_mark_fibers()
  if !major && Heap.verify(h) != 0
    zr_verify_minor()
  end
  zr_fiber_prune()
  zr_weak_prune()
  zr_sweep()
  zr_ages_keep()
  zr_marks_clear()
  live = zr_live_bytes()
  Heap.set_live(h, live)
  if major
    limit = live * OLD_LIMIT_FACTOR
    Heap.set_old_limit(h, limit < OLD_LIMIT_MIN ? OLD_LIMIT_MIN : limit)
  end
  Heap.set_nanoseconds(h, Heap.nanoseconds(h) + (zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC))) - started))
end

# Every arena's marks started from its ages, which is what makes the
# trace of a minor collection stop at what the last one kept.
sig [] => Void
machine def zr_marks_from_ages
  n = Heap.arenas(zr_heap())
  i = 0
  while i < n
    a = zr_arena_at(i)
    zr_memcpy(zr_arena_marks(a), zr_arena_ages(a), MARK_BYTES)
    i += 1
  end
end

# The references of every remembered cell read again. Only the arenas
# the barrier flagged are walked, and a word of the map with no bit in it
# steps over sixty-four cells -- which is what CRuby's
# `rgengc_rememberset_mark` gets from its `remembered_bits`.
sig [] => Void
machine def zr_mark_remembered
  n = Heap.arenas(zr_heap())
  i = 0
  while i < n
    a = zr_arena_at(i)
    if ArenaHead.remembered(a) != 0
      first = zr_arena_first(a)
      bytes = ArenaHead.cell(a)
      map = zr_arena_remembered(a)
      j = 0
      while j < ARENA_CELLS
        word = Machine.load64(map + ((j >> 6) * 8), 0)
        if word == 0 && (j & 63) == 0
          j += 64
        else
          if (word & zr_marks_bit(j)) != 0
            v = Machine.value(first + (j * bytes))
            Machine.store64(zr_marking(), 0, Machine.word(v))
            zr_mark(RBasic.klass(v))
            zr_mark_children(v)
            if (RBasic.flags(v) & FL_EXIVAR) != 0
              zr_mark_ivtab(zr_exivar_tab(v))
            end
          end
          j += 1
        end
      end
    end
    i += 1
  end
end

# Under ZR_GC_VERIFY, what a minor collection marked is held against a
# full trace: an object the full trace reaches and the minor did not is a
# reference into the young that the barrier failed to write down, and it
# is named here, where it was made, instead of turning up as a freed cell
# some collections later. This is the job CRuby gives a whole second
# collector, gc/wbcheck, and it is short here because the barrier is
# emitted and not written by hand.
#
# The remembered map stands in as the scratch: a minor has read it by
# now, and `zr_ages_keep` empties it either way.
sig [] => Void
machine def zr_verify_minor
  n = Heap.arenas(zr_heap())
  i = 0
  while i < n
    a = zr_arena_at(i)
    zr_memcpy(zr_arena_remembered(a), zr_arena_marks(a), MARK_BYTES)
    memset(zr_arena_marks(a), Machine.i32(0), MARK_BYTES)
    i += 1
  end
  Machine.store64(zr_marking(), 0, QNIL)
  Heap.set_verifying(zr_heap(), 1)
  zr_mark_roots()
  zr_mark_drain()
  zr_mark_fibers()
  Heap.set_verifying(zr_heap(), 0)
  i = 0
  while i < n
    zr_verify_arena(zr_arena_at(i))
    i += 1
  end
  i = 0
  while i < n
    a = zr_arena_at(i)
    zr_memcpy(zr_arena_marks(a), zr_arena_remembered(a), MARK_BYTES)
    i += 1
  end
end

# A cell the full trace has just marked. Where the minor collection did
# not mark it, the reference that reached it here is one the write
# barrier failed to write down, and the object that holds it is what
# `zr_marking` names.
sig [Value] => Void
machine def zr_verify_reached(v)
  a = zr_arena_of(v)
  i = zr_cell_index_in(a, v)
  if (Machine.load64(zr_remembered_word(a, i), 0) & zr_marks_bit(i)) != 0
    return
  end
  b = Machine.slot(Buf.size)
  zr_buf_init(b)
  zr_buf_push(b, Machine.bytes("the write barrier missed a store of a cell of type "), 51)
  zr_buf_long(b, RBasic.flags(v) & T_MASK)
  zr_buf_push(b, Machine.bytes(" into "), 6)
  parent = Machine.value(Machine.load64(zr_marking(), 0))
  if zr_fixnum_p(parent)
    zr_buf_push(b, Machine.bytes("root "), 5)
    zr_buf_long(b, zr_fix2long(parent))
  elsif zr_special_p(parent)
    zr_buf_push(b, Machine.bytes("a root"), 6)
  else
    zr_buf_push(b, Machine.bytes("a cell of type "), 15)
    zr_buf_long(b, RBasic.flags(parent) & T_MASK)
  end
  zr_buf_byte(b, 10)
  zr_bug(Buf.ptr(b), Buf.len(b))
end

# Every cell of `a` the full trace reached and the minor did not.
sig [Ptr] => Void
machine def zr_verify_arena(a)
  marks = zr_arena_marks(a)
  minor = zr_arena_remembered(a)
  first = zr_arena_first(a)
  bytes = ArenaHead.cell(a)
  j = 0
  while j < ARENA_CELLS
    missed = Machine.load64(marks + ((j >> 6) * 8), 0) & (0 - 1 - Machine.load64(minor + ((j >> 6) * 8), 0))
    if missed == 0 && (j & 63) == 0
      j += 64
    else
      if (missed & zr_marks_bit(j)) != 0
        b = Machine.slot(Buf.size)
        zr_buf_init(b)
        zr_buf_push(b, Machine.bytes("a minor collection did not reach a live cell of type "), 53)
        zr_buf_long(b, Machine.load64(first + (j * bytes), 0) & T_MASK)
        zr_buf_push(b, Machine.bytes(": the write barrier missed a store into it\n"), 43)
        zr_bug(Buf.ptr(b), Buf.len(b))
      end
      j += 1
    end
  end
end

# A size class is grown where the sweep left it under FREE_FLOOR
# hundredths of its capacity free, and then to FREE_GOAL free. The
# sweep has counted what came free, so every live set is known and the
# heap reaches the size it wants in one step, with nothing to
# overshoot.
#
# `wanting` -- the class whose empty free list ran this collection --
# is grown whatever the sweep left it, and to free cells worth the
# whole heap's live *bytes*. A collection marks every live object, of
# every size, so the allocations it pays for are counted against all of
# them, as they were when the heap had one size. That amortization is
# what the rule before this one argued for and it is right; what was
# wrong was its unit. It counted the heap's live **cells** across four
# classes that hold 32, 64, 128 and 256 bytes, so the 256-byte class
# was handed eight times the room the 32-byte class would have been for
# the same count.
#
# The other half of that rule grew every class to twice its live set on
# every collection whether or not the sweep had already left it room.
# Measured on a program that builds a tree, a collection that freed
# nothing and found the same 141,880 cells live grew that class from 23
# arenas to 36.
#
# Reserved arenas are counted free, so a class holding one is a class
# the last collection already paid for and this one leaves alone. That
# is CRuby's tomb, which `gc_sweep_finish_heap` empties before it asks
# the host for a page.
sig [Word] => Void
machine def zr_heap_grow(wanting)
  # The machine bounds the heap. Once the cells reach their share of it
  # every class is grown to the floor and no further, and none is given
  # the amortization: the collector runs more often instead of asking
  # for memory the host must find somewhere, and a collection costs less
  # than a page-in does.
  pressed = zr_heap_pressed()
  goal = pressed ? FREE_FLOOR : FREE_GOAL
  live_bytes = zr_live_bytes()
  c = 0
  while c < SIZE_CLASSES
    sc = zr_size_class(c)
    capacity = SizeClass.arenas(sc) * ARENA_CELLS
    free = SizeClass.freed(sc)
    live = capacity - free
    want = capacity
    if c == wanting && !pressed
      want = live + (live_bytes / (CELL_MIN << c))
    elsif free * 100 < capacity * FREE_FLOOR
      want = (live * 100) / (100 - goal)
    end
    most = (capacity * GROWTH) / 100
    cells = want < most ? want : most
    while SizeClass.arenas(sc) * ARENA_CELLS < cells
      zr_arena_add(c)
    end
    c += 1
  end
end

# The payload the heap may hold before the next collection runs on that
# account: what it holds now, and a bounded increment over it.
sig [] => Void
machine def zr_malloc_limit_set
  h = zr_heap()
  malloced = Heap.malloced(h)
  grown = (malloced * (MALLOC_GROWTH - 100)) / 100
  step = grown < MALLOC_LIMIT ? MALLOC_LIMIT : grown
  Heap.set_malloc_limit(h, malloced + (step > MALLOC_LIMIT_MAX ? MALLOC_LIMIT_MAX : step))
end

# The payload bytes held, and the count that runs the collector, for
# GC.stat.
sig [] => Value
machine def zr_gc_malloced
  zr_fix(Heap.malloced(zr_heap()))
end

sig [] => Value
machine def zr_gc_malloc_limit
  zr_fix(Heap.malloc_limit(zr_heap()))
end

# The nanoseconds every collection so far has taken.
sig [] => Value
machine def zr_gc_nanoseconds
  zr_fix(Heap.nanoseconds(zr_heap()))
end

# The GC module's view of the heap. `disable` and `enable` answer
# whether collection was disabled before; while it is disabled, the
# heap grows when the cells run out, as CRuby's does.
sig [] => Value
machine def zr_gc_start
  zr_collect_kind(SIZE_CLASSES, true)
  zr_heap_grow(SIZE_CLASSES)
  zr_malloc_limit_set()
  zr_heap_slow_update()
  zr_finalizers_run()
end

sig [] => Value
machine def zr_gc_count
  zr_fix(Heap.collections(zr_heap()))
end

# The objects every size class has handed out.
sig [] => Value
machine def zr_gc_allocated
  n = 0
  c = 0
  while c < SIZE_CLASSES
    n += SizeClass.allocated(zr_size_class(c))
    c += 1
  end
  zr_fix(n)
end

# Size class `c` for GC.stat_heap: its cell size, live cells, free
# cells, arenas and the objects it has handed out. A pool past the
# four has its size and nothing else.
sig [Value] => Value
machine def zr_gc_pool(c)
  i = zr_fix2long(c)
  bytes = CELL_MIN << i
  live = 0
  arenas = 0
  allocated = 0
  if i < SIZE_CLASSES
    sc = zr_size_class(i)
    arenas = SizeClass.arenas(sc)
    allocated = SizeClass.allocated(sc)
    a = 0
    while a < Heap.arenas(zr_heap())
      base = zr_arena_at(a)
      if ArenaHead.index(base) == i && ArenaHead.reserved(base) == 0
        first = zr_arena_first(base)
        j = 0
        while j < ARENA_CELLS
          if (Machine.load64(first + (j * bytes), 0) & FL_ALLOCATED) != 0
            live += 1
          end
          j += 1
        end
      end
      a += 1
    end
  end
  out = zr_ary_new(5)
  zr_ary_push(out, zr_fix(bytes))
  zr_ary_push(out, zr_fix(live))
  zr_ary_push(out, zr_fix((arenas * ARENA_CELLS) - live))
  zr_ary_push(out, zr_fix(arenas))
  zr_ary_push(out, zr_fix(allocated))
  out
end

sig [] => Value
machine def zr_gc_arenas
  zr_fix(Heap.arenas(zr_heap()))
end

# The cells of every arena, of every size.
sig [] => Word
machine def zr_heap_cells
  Heap.arenas(zr_heap()) * ARENA_CELLS
end

sig [Value] => Value
machine def zr_gc_set_disabled(flag)
  h = zr_heap()
  was = zr_bool(Heap.disabled(h) != 0)
  Heap.set_disabled(h, flag == QTRUE ? 1 : 0)
  was
end

sig [Value] => Value
machine def zr_gc_set_stress(flag)
  h = zr_heap()
  Heap.set_stress(h, flag == QNIL || flag == QFALSE ? 0 : 1)
  zr_heap_slow_update()
  flag
end

sig [] => Value
machine def zr_gc_stress
  zr_bool(Heap.stress(zr_heap()) != 0)
end

# A cell of `type` whose class is `klass`, from the smallest size class
# that holds `bytes`, the payload as the free list left it: the
# constructor writes every field before anything can collect or read
# the cell, and under stress the payload is poison, so a field it left
# out reads as 0xDEAD, not as an empty one. The caller stores the
# result to its frame record before anything else can allocate.
#
# Inlined at every allocation: the head of the free list when there is
# one and `Heap.slow` is clear, else `zr_alloc_slow`.
sig [Word, Value, Word] => Value
machine def zr_alloc(type, klass, bytes)
  sc = zr_size_class(zr_size_class_for(bytes))
  cell = SizeClass.free(sc)
  if cell == 0 || Heap.slow(zr_heap()) != 0
    zr_alloc_slow(type, klass, bytes)
  else
    zr_cell_take(sc, cell, type, klass)
  end
end
Machine.inline :zr_alloc

# `cell`, the head of size class `sc`'s free list, off the list with its
# header written.
sig [Ptr, Ptr, Word, Value] => Value
machine def zr_cell_take(sc, cell, type, klass)
  SizeClass.set_free(sc, Machine.load64(cell, 8))
  SizeClass.set_last(sc, cell)
  SizeClass.set_allocated(sc, SizeClass.allocated(sc) + 1)
  Machine.store64(cell, 0, type | FL_ALLOCATED)
  Machine.store64(cell, 8, Machine.word(klass))
  Machine.value(cell)
end

# Whether an allocation must take `zr_alloc_slow`: under stress, while
# allocations are traced, or once the payload passes its limit.
# Written again wherever one of the three changes.
sig [] => Void
machine def zr_heap_slow_update
  h = zr_heap()
  slow = Heap.stress(h) != 0 || AllocTrace.on(zr_alloc_trace()) != 0 || Heap.malloced(h) > Heap.malloc_limit(h)
  Heap.set_slow(h, slow ? 1 : 0)
end

# An allocation `zr_alloc` does not serve in place: a collection when
# the list is empty, the payload is past its limit or stress asks for
# one, the poison of stress and the trace's row.
sig [Word, Value, Word] => Value
machine def zr_alloc_slow(type, klass, bytes)
  h = zr_heap()
  c = zr_size_class_for(bytes)
  sc = zr_size_class(c)
  # A stress collection runs at every allocation whatever the room, so
  # it asks for no more than the plain growth; the room it would buy
  # only lengthens the next sweep.
  if Heap.stress(h) != 0 && Heap.disabled(h) == 0
    zr_collect(SIZE_CLASSES)
  end
  # An empty list takes a reserved arena before it takes a collection:
  # the reserve is room the last collection already paid for.
  if SizeClass.free(sc) == 0
    zr_arena_unreserve(sc)
  end
  if (SizeClass.free(sc) == 0 || Heap.malloced(h) > Heap.malloc_limit(h)) && Heap.disabled(h) == 0
    zr_collect(c)
    zr_arena_unreserve(sc)
  end
  cell = SizeClass.free(sc)
  if cell == 0
    zr_arena_add(c)
    zr_arena_unreserve(sc)
    cell = SizeClass.free(sc)
  end
  v = zr_cell_take(sc, cell, type, klass)
  if Heap.stress(h) != 0
    zr_poison_payload(cell, CELL_MIN << c)
  end
  if AllocTrace.on(zr_alloc_trace()) != 0
    zr_alloc_trace_record(cell)
  end
  zr_heap_slow_update()
  v
end

# Every kernel function that may run the collector keeps its Values in
# a root frame (`prev, n, values...`) the compiler links from here.
Machine.collects :zr_collect
Machine.collects :zr_collect_kind

sig [] => Ptr
machine def zr_kroots
  Machine.static(:kroots, 8)
end

sig [] => Void
machine def zr_mark_kernel_roots
  zr_mark_kernel_roots_from(Machine.ptr(Machine.load64(zr_kroots(), 0)))
end

sig [Ptr] => Void
machine def zr_mark_kernel_roots_from(frame)
  while frame != 0
    n = Machine.load64(frame, 8)
    i = 0
    while i < n
      zr_mark(Machine.value(Machine.load64(frame + 16 + (i * 8), 0)))
      i += 1
    end
    frame = Machine.ptr(Machine.load64(frame, 0))
  end
end

# `global_variables`: every name with a row, and every alias of one.
sig [] => Value
machine def zr_global_variables
  out = zr_ary_new(16)
  zr_ivtab_names(zr_gvars(), out, 36)
  zr_ivtab_names(zr_gvar_aliases(), out, 36)
  out
end
