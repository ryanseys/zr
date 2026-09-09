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
Machine.struct :Heap, free: Ptr, allocated: Word, collections: Word, stress: Word, last: Word, disabled: Word

sig [] => Ptr
machine def zr_heap
  Machine.static(:heap, Heap.size)
end

sig [] => Ptr
machine def zr_arena
  Machine.static(:arena, ARENA_BYTES)
end

# The frame chain the collector walks: a record is a Frame followed by
# `nvalues` Values.
# `mid` is the name a method frame was called by, an alias's own.
Machine.struct :Frame, prev: Ptr, meta: Ptr, line: Word, serial: Word, self: Value, cref: Value, blk: Value, nvalues: Word, mid: Word
Machine.struct :Task, top: Ptr, serial: Word, pending: Value, errinfo: Value, pending_kind: Word, pending_home: Ptr, pending_site: Word, kw: Word, stack_limit: Ptr, guards: Value, catches: Value, throw_tag: Value, mid: Word

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
G_COUNT = 40

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

# The object whose children are being marked, so the abort below can
# name what pointed at a freed cell.
sig [] => Ptr
machine def zr_marking
  Machine.static(:marking, 8)
end

sig [Value] => Void
machine def zr_mark(v)
  unless zr_special_p(v)
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
    if (flags & FL_MARK) == 0
      RBasic.set_flags(v, flags | FL_MARK)
      zr_mark(RBasic.klass(v))
      was = Machine.load64(zr_marking(), 0)
      Machine.store64(zr_marking(), 0, Machine.word(v))
      zr_mark_children(v)
      Machine.store64(zr_marking(), 0, was)
      if (flags & FL_EXIVAR) != 0
        zr_mark_ivtab(zr_exivar_tab(v))
      end
    end
  end
end

# The ivar tables of objects whose kind has none of its own: one slot
# per cell, holding a table or 0.
sig [] => Ptr
machine def zr_exivars
  Machine.static(:exivars, CELLS * 8)
end

sig [Value] => Ptr
machine def zr_exivar_slot(v)
  zr_exivars() + (((Machine.word(v) - zr_arena()) / CELL) * 8)
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
    t = malloc(IvTab.size)
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
  free(t)
  Machine.store64(zr_exivar_slot(v), 0, 0)
end

# Global variables: one table of (id, value) rows.
sig [] => Ptr
machine def zr_gvars
  Machine.static(:gvars, IvTab.size)
end

sig [Word] => Value
machine def zr_gvar_get(id)
  v = zr_ivtab_get(zr_gvars(), id)
  if v == QUNDEF
    return Machine.value(QNIL)
  end
  v
end

sig [Word] => Value
machine def zr_gvar_defined(id)
  zr_bool(zr_ivtab_row(zr_gvars(), id) != 0)
end

sig [Word, Value] => Value
machine def zr_gvar_set(id, v)
  zr_ivtab_set(zr_gvars(), id, v)
  v
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
  zr_mark_task(zr_task())
  Machine.store64(zr_marking(), 0, Machine.word(zr_fix(3)))
  zr_mark_kernel_roots()
end

# A task's roots: its slots and its frame chain.
sig [Ptr] => Void
machine def zr_mark_task(t)
  zr_mark(Task.pending(t))
  zr_mark(Task.errinfo(t))
  zr_mark(Task.guards(t))
  zr_mark(Task.catches(t))
  zr_mark(Task.throw_tag(t))
  rec = Task.top(t)
  while rec != 0
    Machine.store64(zr_marking(), 0, Machine.word(zr_fix(4)))
    zr_mark(Frame.self(rec))
    zr_mark(Frame.cref(rec))
    zr_mark(Frame.blk(rec))
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
      if (flags & FL_EXIVAR) != 0
        zr_exivar_free(Machine.value(cell))
      end
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
  Machine.store64(zr_marking(), 0, QNIL)
  zr_mark_roots()
  zr_sweep()
end

# The GC module's view of the heap. `disable` and `enable` answer
# whether collection was disabled before; a disabled collector still
# runs when the cells run out.
sig [] => Value
machine def zr_gc_start
  zr_collect()
  Machine.value(QNIL)
end

sig [] => Value
machine def zr_gc_count
  zr_fix(Heap.collections(zr_heap()))
end

sig [] => Value
machine def zr_gc_allocated
  zr_fix(Heap.allocated(zr_heap()))
end

sig [] => Value
machine def zr_gc_live_slots
  n = 0
  i = 0
  while i < CELLS
    if (Machine.load64(zr_arena() + (i * CELL), 0) & FL_ALLOCATED) != 0
      n += 1
    end
    i += 1
  end
  zr_fix(n)
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
  flag
end

sig [] => Value
machine def zr_gc_stress
  zr_bool(Heap.stress(zr_heap()) != 0)
end

# A cell of `type` whose class is `klass`, zeroed past the header. The
# caller stores the result to its frame record before anything else can
# allocate.
sig [Word, Value] => Value
machine def zr_alloc(type, klass)
  h = zr_heap()
  if Heap.stress(h) != 0 && Heap.disabled(h) == 0
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
