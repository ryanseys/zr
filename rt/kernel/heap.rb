# The heap: cells of one size from arenas through a free list; a
# precise mark-sweep collector rooted in the task's frame records and
# the globals. A freed cell is poisoned and loses FL_ALLOCATED, and
# marking aborts on a reference to one: a live object pointing at a
# freed cell is a root the discipline missed. Under ZR_GC_STRESS every
# allocation collects first, and the free list starts just past the
# last cell handed out, so a stale pointer meets the poison, not a new
# object.
#
# An arena is ARENA_BYTES of cells aligned to its own size, so a cell's
# arena is its address with the low bits cleared; the arena's exivar
# slots follow its cells. The collector runs when the free list is
# empty, and grows the heap to twice what the sweep found live.
CELL = 128
CELLS = 32768
ARENA_BYTES = CELL * CELLS
ARENA_ALLOC = ARENA_BYTES + CELLS * 8
ARENA_LIMIT = 1024
POISON = 57005 << 8

# Heap state: free head, allocations, collections, stress flag, the
# last cell handed out, the arena count, the cells the last sweep freed.
Machine.struct :Heap, free: Ptr, allocated: Word, collections: Word, stress: Word, last: Ptr, disabled: Word, arenas: Word, freed: Word, nanoseconds: Word

sig [] => Ptr
machine def zr_heap
  Machine.static(:heap, Heap.size)
end

sig [] => Ptr
machine def zr_arenas
  Machine.static(:arenas, ARENA_LIMIT * 8)
end

sig [Word] => Ptr
machine def zr_arena_at(i)
  Machine.ptr(Machine.load64(zr_arenas() + (i * 8), 0))
end

sig [Value] => Ptr
machine def zr_arena_of(v)
  Machine.ptr(Machine.word(v) & (0 - ARENA_BYTES))
end

# A new arena of poisoned cells pushed onto the free list in address
# order.
sig [] => Void
machine def zr_arena_add
  h = zr_heap()
  n = Heap.arenas(h)
  if n == ARENA_LIMIT
    zr_memory_exhausted()
  end
  slot = Machine.slot(8)
  if posix_memalign(slot, ARENA_BYTES, ARENA_ALLOC) != Machine.i32(0)
    zr_memory_exhausted()
  end
  a = Machine.ptr(Machine.load64(slot, 0))
  Machine.store64(zr_arenas() + (n * 8), 0, Machine.word(a))
  Heap.set_arenas(h, n + 1)
  head = Heap.free(h)
  i = CELLS - 1
  while i >= 0
    cell = a + (i * CELL)
    Machine.store64(cell, 0, POISON)
    Machine.store64(cell, 8, head)
    Machine.store64(a + ARENA_BYTES + (i * 8), 0, 0)
    head = cell
    i -= 1
  end
  Heap.set_free(h, head)
end

# The frame chain the collector walks: a record is a Frame followed by
# `nvalues` Values.
# `mid` is the name a method frame was called by, an alias's own.
# `defined` is the class or proxy the method was found in, which `super`
# continues from (a module included twice has two proxies).
Machine.struct :Frame, prev: Ptr, meta: Ptr, line: Word, serial: Word, self: Value, cref: Value, blk: Value, nvalues: Word, mid: Word, svar: Value, lastline: Value, defined: Value
Machine.struct :Task, top: Ptr, serial: Word, pending: Value, errinfo: Value, pending_kind: Word, pending_home: Ptr, pending_site: Word, kw: Word, stack_limit: Ptr, guards: Value, catches: Value, throw_tag: Value, mid: Word, missing: Word, found: Value, refine: Value, ractor: Word

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
G_COUNT = 60

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
  zr_arena_add()
  Heap.set_last(h, zr_arena_at(0) + ((CELLS - 1) * CELL))
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
# a cell still to mark costs a call.
sig [Value] => Void
machine def zr_mark(v)
  unless zr_special_p(v) || (RBasic.flags(v) & MARKED) == MARKED
    zr_mark_cell(v)
  end
end

# The flags of a live, marked cell.
MARKED = FL_ALLOCATED | FL_MARK

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
  if (flags & FL_MARK) != 0
    return
  end
  RBasic.set_flags(v, flags | FL_MARK)
  s = zr_mark_stack()
  n = MarkStack.len(s)
  if n == MarkStack.capa(s)
    capa = n == 0 ? 1024 : n * 2
    grown = zr_xmalloc(capa * 8)
    if n > 0
      zr_memcpy(grown, MarkStack.ptr(s), n * 8)
      free(MarkStack.ptr(s))
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
  a = zr_arena_of(v)
  a + ARENA_BYTES + (((Machine.word(v) - a) / CELL) * 8)
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
  free(t)
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
    zr_mark(Frame.svar(rec))
    zr_mark(Frame.lastline(rec))
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

# Free an unmarked cell that was live: release what it owns, and poison
# it.
sig [Ptr] => Void
machine def zr_free_cell(cell)
  flags = Machine.load64(cell, 0)
  if (flags & FL_ALLOCATED) != 0
    zr_release(Machine.value(cell))
    if (flags & FL_EXIVAR) != 0
      zr_exivar_free(Machine.value(cell))
    end
  end
  Machine.store64(cell, 0, POISON)
  # The header's poison is what mark checks; the payload's is only there
  # to make a stale read loud, which stress mode is for.
  if Heap.stress(zr_heap()) != 0
    j = 16
    while j < CELL
      Machine.store64(cell + j, 0, 57005)
      j += 8
    end
  end
end

# The cells of an arena from `stop` down to `start`, pushed in reverse
# so the list pops in address order. A marked cell only loses its mark,
# and a cell freed before keeps its poison and takes only the link, so
# the loop calls out for a cell that dies in this collection alone.
sig [Ptr, Word, Word] => Void
machine def zr_sweep_arena(a, start, stop)
  h = zr_heap()
  free = Heap.free(h)
  freed = Heap.freed(h)
  i = stop
  while i >= start
    cell = a + (i * CELL)
    flags = Machine.load64(cell, 0)
    if (flags & FL_MARK) != 0
      Machine.store64(cell, 0, flags & (0 - (FL_MARK + 1)))
    else
      if flags != POISON
        zr_free_cell(cell)
      end
      Machine.store64(cell, 8, free)
      free = cell
      freed += 1
    end
    i -= 1
  end
  Heap.set_free(h, free)
  Heap.set_freed(h, freed)
end

# Every arena's cells, the list starting at the cell after the last one
# handed out: its arena's tail, then the other arenas, then its arena's
# head.
sig [] => Void
machine def zr_sweep
  h = zr_heap()
  last = Heap.last(h)
  home = zr_arena_of(Machine.value(last))
  split = (last - home) / CELL
  n = Heap.arenas(h)
  Heap.set_free(h, 0)
  Heap.set_freed(h, 0)
  zr_sweep_arena(home, 0, split)
  i = n - 1
  while i >= 0
    a = zr_arena_at(i)
    if a != home
      zr_sweep_arena(a, 0, CELLS - 1)
    end
    i -= 1
  end
  zr_sweep_arena(home, split + 1, CELLS - 1)
end

# Collect; then grow to twice the live set, which is the capacity that
# leaves half the cells free for the round after this one. The sweep
# counted what came free, so the live set is known and the heap reaches
# the size it wants in one step, with nothing to overshoot.
sig [] => Void
machine def zr_collect
  h = zr_heap()
  started = zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC)))
  Heap.set_collections(h, Heap.collections(h) + 1)
  Machine.store64(zr_marking(), 0, QNIL)
  zr_mark_roots()
  zr_mark_drain()
  zr_weak_prune()
  zr_sweep()
  live =(Heap.arenas(h) * CELLS) - Heap.freed(h)
  want = ((live * 2) + (CELLS - 1)) / CELLS
  while Heap.arenas(h) < want && Heap.arenas(h) < ARENA_LIMIT
    zr_arena_add()
  end
  Heap.set_nanoseconds(h, Heap.nanoseconds(h) + (zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC))) - started))
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
  zr_collect()
  zr_finalizers_run()
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
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    i = 0
    while i < CELLS
      if (Machine.load64(base + (i * CELL), 0) & FL_ALLOCATED) != 0
        n += 1
      end
      i += 1
    end
    a += 1
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
  if Heap.free(h) == 0 && Heap.disabled(h) == 0
    zr_collect()
  end
  cell = Heap.free(h)
  if cell == 0
    zr_arena_add()
    cell = Heap.free(h)
  end
  Heap.set_free(h, Machine.load64(cell, 8))
  Heap.set_last(h, cell)
  Heap.set_allocated(h, Heap.allocated(h) + 1)
  Machine.store64(cell, 0, type | FL_ALLOCATED)
  Machine.store64(cell, 8, Machine.word(klass))
  memset(cell + 16, Machine.i32(0), CELL - 16)
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

# `global_variables`: every name with a row, and every alias of one.
sig [] => Value
machine def zr_global_variables
  out = zr_ary_new(16)
  zr_ivtab_names(zr_gvars(), out, 36)
  zr_ivtab_names(zr_gvar_aliases(), out, 36)
  out
end
