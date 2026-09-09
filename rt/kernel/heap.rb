# The heap: cells of one size from a static arena through a free list;
# a precise mark-sweep collector rooted in the task's frame records and
# the globals. A freed cell is poisoned and loses FL_ALLOCATED, and
# marking aborts on a reference to one: a live object pointing at a
# freed cell is a root the discipline missed. Under ZR_GC_STRESS every
# allocation collects first, and the free list starts just past the
# last cell handed out, so a stale pointer meets the poison, not a new
# object.
CELL = 128
CELLS = 32768
ARENA_BYTES = CELL * CELLS
POISON = 57005 << 8

# Heap state: free head, allocations, collections, stress flag, the
# index of the last cell handed out.
Machine.struct :Heap, free: Ptr, allocated: Word, collections: Word, stress: Word, last: Word

sig [] => Ptr
machine def zr_heap
  Machine.static(:heap, 64)
end

sig [] => Ptr
machine def zr_arena
  Machine.static(:arena, ARENA_BYTES)
end

# The frame chain the collector walks: a record is a Frame followed by
# `nvalues` Values.
Machine.struct :Frame, prev: Ptr, meta: Ptr, line: Word, serial: Word, self: Value, cref: Value, blk: Value, nvalues: Word
Machine.struct :Task, top: Ptr, serial: Word, pending: Value, errinfo: Value, pending_kind: Word, pending_home: Ptr, pending_site: Word, kw: Word

sig [] => Ptr
machine def zr_task
  Machine.static(:task, 64)
end

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
G_COUNT = 32

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

sig [] => Void
machine def zr_heap_init
  h = zr_heap()
  a = zr_arena()
  i = 0
  head = 0
  while i < CELLS
    cell = a + (i * CELL)
    Machine.store64(cell, 0, POISON)
    Machine.store64(cell, 8, head)
    head = cell
    i += 1
  end
  Heap.set_free(h, head)
  Heap.set_last(h, CELLS - 1)
  if getenv(Machine.bytes("ZR_GC_STRESS\0")) != 0
    Heap.set_stress(h, 1)
  end
end

sig [Value] => Void
machine def zr_mark(v)
  unless zr_special_p(v)
    flags = RBasic.flags(v)
    if (flags & FL_ALLOCATED) == 0
      zr_bug(Machine.bytes("a live object points at a freed cell\n"), 37)
    end
    if (flags & FL_MARK) == 0
      RBasic.set_flags(v, flags | FL_MARK)
      zr_mark(RBasic.klass(v))
      zr_mark_children(v)
    end
  end
end

sig [] => Void
machine def zr_mark_roots
  i = 0
  while i < G_COUNT
    zr_mark(zr_global(i))
    i += 1
  end
  zr_mark(Task.pending(zr_task()))
  zr_mark(Task.errinfo(zr_task()))
  zr_mark_kernel_roots()
  rec = Task.top(zr_task())
  while rec != 0
    zr_mark(Frame.self(rec))
    zr_mark(Frame.cref(rec))
    zr_mark(Frame.blk(rec))
    n = Frame.nvalues(rec)
    i = 0
    while i < n
      zr_mark(Machine.value(Machine.load64(rec + Frame.size + (i * 8), 0)))
      i += 1
    end
    rec = Frame.prev(rec)
  end
end

sig [Word] => Void
machine def zr_free_cell(i)
  h = zr_heap()
  cell = zr_arena() + (i * CELL)
  flags = Machine.load64(cell, 0)
  if (flags & FL_MARK) != 0
    Machine.store64(cell, 0, flags & (0 - (FL_MARK + 1)))
  else
    if (flags & FL_ALLOCATED) != 0
      zr_release(Machine.value(cell))
    end
    Machine.store64(cell, 0, POISON)
    Machine.store64(cell, 8, Heap.free(h))
    j = 16
    while j < CELL
      Machine.store64(cell + j, 0, 57005)
      j += 8
    end
    Heap.set_free(h, cell)
  end
end

# Push the cells in reverse, so the list pops in address order from the
# cell after the last one handed out.
sig [] => Void
machine def zr_sweep
  h = zr_heap()
  last = Heap.last(h)
  Heap.set_free(h, 0)
  i = last
  while i >= 0
    zr_free_cell(i)
    i -= 1
  end
  i = CELLS - 1
  while i > last
    zr_free_cell(i)
    i -= 1
  end
end

sig [] => Void
machine def zr_collect
  h = zr_heap()
  Heap.set_collections(h, Heap.collections(h) + 1)
  zr_mark_roots()
  zr_sweep()
end

# A cell of `type` whose class is `klass`, zeroed past the header. The
# caller stores the result to its frame record before anything else can
# allocate.
sig [Word, Value] => Value
machine def zr_alloc(type, klass)
  h = zr_heap()
  if Heap.stress(h) != 0
    zr_collect()
  end
  if Heap.free(h) == 0
    zr_collect()
  end
  cell = Heap.free(h)
  if cell == 0
    zr_bug(Machine.bytes("out of cells\n"), 13)
  end
  Heap.set_free(h, Machine.load64(cell, 8))
  Heap.set_last(h, (cell - zr_arena()) / CELL)
  Heap.set_allocated(h, Heap.allocated(h) + 1)
  Machine.store64(cell, 0, type | FL_ALLOCATED)
  Machine.store64(cell, 8, Machine.word(klass))
  j = 16
  while j < CELL
    Machine.store64(cell + j, 0, 0)
    j += 8
  end
  Machine.value(cell)
end

# Every kernel function that may run the collector keeps its Values in
# a root frame (`prev, n, values...`) the compiler links from here.
Machine.collects :zr_collect

sig [] => Ptr
machine def zr_kroots
  Machine.static(:kroots, 8)
end

sig [] => Void
machine def zr_mark_kernel_roots
  frame = Machine.ptr(Machine.load64(zr_kroots(), 0))
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
