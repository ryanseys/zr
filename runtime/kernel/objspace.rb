# ObjectSpace's view of the heap: the objects that a walk yields, the
# count by type, the object for an id, and the objects that one object
# refers to. A walk copies the objects it finds into an Array before any
# Ruby code runs, as gc.c's os_obj_of does. Thus a block that allocates
# never sees a cell that it made.

# Whether cell `v` is an object that a program can get, as
# internal_object_p decides. It is not a runtime record, not a hidden
# object, and not the singleton class of a class while that singleton
# class has no singleton class of its own.
sig [Value] => Bool
machine def zr_objspace_visible_p(v)
  t = RBasic.flags(v) & T_MASK
  if t == T_NONE || t == T_CREF || t == T_ENV || t == T_ICLASS
    return false
  end
  klass = RBasic.klass(v)
  if Machine.word(klass) == 0 || zr_special_p(klass)
    return false
  end
  if (RBasic.flags(v) & FL_CONCEALED) != 0 || (RBasic.flags(klass) & FL_CONCEALED) != 0
    return false
  end
  if t == T_CLASS && (RBasic.flags(v) & FL_SINGLETON) != 0
    attached = RClass.attached(v)
    if !zr_special_p(attached) && (RBasic.flags(attached) & T_MASK) == T_CLASS
      return (RBasic.flags(klass) & FL_SINGLETON) != 0 && RClass.attached(klass) == v
    end
  end
  true
end

# All live objects that a program can get, only of `mod` if it is not nil.
sig [Value] => Value
machine def zr_objspace_objects(mod)
  out = zr_ary_new(1024)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = zr_arena_next_allocated(base, 0)
    while i < ARENA_CELLS
      v = Machine.value(first + (i * bytes))
      if Machine.word(v) != Machine.word(out) && zr_objspace_visible_p(v)
        if mod == QNIL || zr_is_a(v, mod)
          zr_ary_push(out, v)
        end
      end
      i = zr_arena_next_allocated(base, i + 1)
    end
    a += 1
  end
  out
end

# The heap by type: the total cells, the free cells, then the live cells
# of each of the 32 type tags.
sig [] => Value
machine def zr_objspace_census
  counts = Machine.slot(32 * 8)
  memset(counts, Machine.i32(0), 32 * 8)
  live_cells = 0
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = zr_arena_next_allocated(base, 0)
    while i < ARENA_CELLS
      flags = Machine.load64(first + (i * bytes), 0)
      slot = counts + ((flags & T_MASK) * 8)
      Machine.store64(slot, 0, Machine.load64(slot, 0) + 1)
      live_cells += 1
      i = zr_arena_next_allocated(base, i + 1)
    end
    a += 1
  end
  out = zr_ary_new(34)
  zr_ary_push(out, zr_fix(zr_heap_cells()))
  zr_ary_push(out, zr_fix(zr_heap_cells() - live_cells))
  t = 0
  while t < 32
    zr_ary_push(out, zr_fix(Machine.load64(counts + (t * 8), 0)))
    t += 1
  end
  out
end

# The live object whose object_id is `id`, or nil. An object has an id
# only after a call to its object_id.
sig [Value] => Value
machine def zr_objspace_id2ref(id)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = zr_arena_next_allocated(base, 0)
    while i < ARENA_CELLS
      v = Machine.value(first + (i * bytes))
      if zr_objspace_visible_p(v)
        t = zr_ivtab(v)
        if t != 0 && zr_ivtab_get(t, Machine.id(:__object_id__)) == id
          return v
        end
      end
      i = zr_arena_next_allocated(base, i + 1)
    end
    a += 1
  end
  Machine.value(QNIL)
end

# The objects that `v` refers to, as the collector reads them: its class,
# then its children in mark order, each one time. The mark puts them on
# the mark stack, where this code reads them and clears their marks. No
# cell is marked outside a collection, so each child is new to the
# stack.
sig [Value] => Value
machine def zr_objspace_reachable(v)
  out = zr_ary_new(8)
  if zr_special_p(v)
    return out
  end
  s = zr_mark_stack()
  from = MarkStack.len(s)
  Machine.store64(zr_mark_every(), 0, 1)
  zr_mark(RBasic.klass(v))
  zr_mark_children(v)
  if (RBasic.flags(v) & FL_EXIVAR) != 0
    zr_mark_ivtab(zr_exivar_tab(v))
  end
  Machine.store64(zr_mark_every(), 0, 0)
  i = from
  while i < MarkStack.len(s)
    child = Machine.value(Machine.load64(MarkStack.ptr(s) + (i * 8), 0))
    zr_mark_unset(child)
    if zr_objspace_visible_p(child)
      zr_ary_push(out, child)
    end
    i += 1
  end
  MarkStack.set_len(s, from)
  out
end

# The objects that the collector's roots reach first, by the kind of
# root, as ObjectSpace.reachable_objects_from_root groups them: the
# runtime's roots (its classes and the main object), the global
# variables, the objects in the running fibers and the kernel's frames,
# and the finalizers. This makes each cell of the result before the
# first mark, because a collection must not start while this walk owns
# the marks.
sig [] => Value
machine def zr_objspace_roots
  out = zr_hash_new()
  vm = zr_ary_new(64)
  globals = zr_ary_new(16)
  context = zr_ary_new(64)
  finalizers = zr_ary_new(4)
  zr_hash_store(out, zr_str_new(Machine.bytes("vm"), 2), vm)
  zr_hash_store(out, zr_str_new(Machine.bytes("global_tbl"), 10), globals)
  zr_hash_store(out, zr_str_new(Machine.bytes("machine_context"), 15), context)
  zr_hash_store(out, zr_str_new(Machine.bytes("finalizers"), 10), finalizers)
  s = zr_mark_stack()
  from = MarkStack.len(s)
  Machine.store64(zr_mark_every(), 0, 1)
  i = 0
  while i < G_COUNT
    zr_mark(zr_global(i))
    i += 1
  end
  zr_objspace_take(s, from, vm, out)
  zr_mark_ivtab(zr_gvars())
  zr_objspace_take(s, from, globals, out)
  zr_mark(Machine.value(Machine.load64(Machine.static(:current_fiber, 8), 0)))
  zr_mark(Machine.value(Machine.load64(Machine.static(:root_fiber, 8), 0)))
  zr_mark_task(zr_task())
  zr_mark_kernel_roots()
  zr_objspace_take(s, from, context, out)
  zr_mark_finalizer_queue()
  zr_objspace_take(s, from, finalizers, out)
  Machine.store64(zr_mark_every(), 0, 0)
  out
end

# Clears the marks of the cells marked since `from`, and adds the cells
# that a program can see to `into`. The result `out` and its keys and
# values are not added.
sig [Ptr, Word, Value, Value] => Void
machine def zr_objspace_take(s, from, into, out)
  i = from
  while i < MarkStack.len(s)
    child = Machine.value(Machine.load64(MarkStack.ptr(s) + (i * 8), 0))
    zr_mark_unset(child)
    if zr_objspace_visible_p(child) && child != out && !zr_objspace_row_p(out, child)
      zr_ary_push(into, child)
    end
    i += 1
  end
  MarkStack.set_len(s, from)
end

# Whether `v` is one of the keys or values of the result `out`.
sig [Value, Value] => Bool
machine def zr_objspace_row_p(out, v)
  i = 0
  while i < RHash.len(out)
    e = RHash.entries(out) + (i * HEntry.size)
    if HEntry.key(e) == v || HEntry.value(e) == v
      return true
    end
    i += 1
  end
  false
end

# The superclass pointer of `klass`, as the collector follows it. If it
# is the hidden class that an included module makes, this returns its
# address, which ObjectSpace wraps, because no program can get the
# hidden class.
sig [Value] => Value
machine def zr_objspace_super(klass)
  s = RClass.superclass(klass)
  if Machine.word(s) == 0 || s == QNIL
    return Machine.value(QNIL)
  end
  if zr_type(s) == T_ICLASS
    return zr_fix(Machine.word(s))
  end
  s
end

# The bytes that `v` uses: its cell, and the buffer that a String, an
# Array or a Hash keeps outside the cell. An immediate uses none.
sig [Value] => Value
machine def zr_objspace_memsize(v)
  if zr_special_p(v)
    return zr_fix(0)
  end
  t = RBasic.flags(v) & T_MASK
  n = zr_cell_bytes(v)
  if t == T_STRING
    n += zr_str_embedded_p(v) ? 0 : RString.capa(v) + 1
  elsif t == T_ARRAY
    n += zr_ary_embedded_p(v) ? 0 : RArray.capa(v) * 8
  elsif t == T_HASH
    n += (RHash.cap(v) * HEntry.size) + (RHash.nbins(v) * 8)
  end
  zr_fix(n)
end

# ObjectSpace.trace_object_allocations: the source location of each cell
# allocated while tracing is on. The records are outside the heap, with
# the cell's address as the key, so a record allocates no cell. The
# record of a cell goes away when the cell is freed.
Machine.struct :AllocTrace, rows: Ptr, capa: Word, used: Word, on: Word
# `meta` is the C method that made the cell, or 0 if Ruby code made it.
Machine.struct :AllocRow, cell: Word, file: Ptr, file_len: Word, line: Word, meta: Ptr, generation: Word
# Marks a record whose cell was freed. A probe skips it.
ALLOC_GONE = 1

sig [] => Ptr
machine def zr_alloc_trace
  Machine.static(:alloc_trace, AllocTrace.size)
end

# The record for `cell`, or the free record for a new one. At most half
# of the table contains records, freed ones included, so a probe always
# finds an empty record.
sig [Ptr, Word] => Ptr
machine def zr_alloc_trace_probe(t, cell)
  mask = AllocTrace.capa(t) - 1
  i = ((cell / CELL_MIN) * 2654435761) & mask
  row = AllocTrace.rows(t) + (i * AllocRow.size)
  free_row = 0
  while AllocRow.cell(row) != cell && AllocRow.cell(row) != 0
    if AllocRow.cell(row) == ALLOC_GONE && free_row == 0
      free_row = row
    end
    i = (i + 1) & mask
    row = AllocTrace.rows(t) + (i * AllocRow.size)
  end
  if AllocRow.cell(row) == 0 && free_row != 0
    return free_row
  end
  row
end

# Makes space for one more record. When half of the table is used, the
# table doubles, and it does not copy the freed records.
sig [Ptr] => Void
machine def zr_alloc_trace_room(t)
  if (AllocTrace.used(t) + 1) * 2 <= AllocTrace.capa(t)
    return
  end
  old = AllocTrace.rows(t)
  old_capa = AllocTrace.capa(t)
  capa = old_capa == 0 ? 1024 : old_capa * 2
  AllocTrace.set_rows(t, zr_xmalloc(capa * AllocRow.size))
  memset(AllocTrace.rows(t), Machine.i32(0), capa * AllocRow.size)
  AllocTrace.set_capa(t, capa)
  AllocTrace.set_used(t, 0)
  i = 0
  while i < old_capa
    row = old + (i * AllocRow.size)
    if AllocRow.cell(row) > ALLOC_GONE
      zr_memcpy(zr_alloc_trace_probe(t, AllocRow.cell(row)), row, AllocRow.size)
      AllocTrace.set_used(t, AllocTrace.used(t) + 1)
    end
    i += 1
  end
  if old != 0
    zr_xfree(old)
  end
end

# Records a new `cell`: the file and line of the top Ruby frame, and the
# C method that made it, if the top frame is a C method.
sig [Ptr] => Void
machine def zr_alloc_trace_record(cell)
  top = Task.top(zr_task())
  rec = zr_frame_with_file(top)
  if rec == 0
    return
  end
  t = zr_alloc_trace()
  zr_alloc_trace_room(t)
  row = zr_alloc_trace_probe(t, cell)
  if AllocRow.cell(row) != cell
    AllocTrace.set_used(t, AllocTrace.used(t) + 1)
  end
  meta = Frame.meta(rec)
  AllocRow.set_cell(row, cell)
  AllocRow.set_file(row, FrameMeta.file(meta))
  AllocRow.set_file_len(row, FrameMeta.file_len(meta))
  AllocRow.set_line(row, zr_frame_line(rec))
  AllocRow.set_meta(row, top == rec ? 0 : zr_method_meta_of(top))
  AllocRow.set_generation(row, Heap.collections(zr_heap()))
end

# Removes the record of a freed cell.
sig [Ptr] => Void
machine def zr_alloc_trace_forget(cell)
  t = zr_alloc_trace()
  row = zr_alloc_trace_probe(t, cell)
  if AllocRow.cell(row) == cell
    AllocRow.set_cell(row, ALLOC_GONE)
  end
end

sig [Value] => Ptr
machine def zr_alloc_trace_row(v)
  t = zr_alloc_trace()
  if zr_special_p(v) || AllocTrace.used(t) == 0
    return 0
  end
  row = zr_alloc_trace_probe(t, Machine.word(v))
  AllocRow.cell(row) == Machine.word(v) ? row : 0
end

sig [Value] => Value
machine def zr_alloc_trace_set(on)
  AllocTrace.set_on(zr_alloc_trace(), on == QTRUE ? 1 : 0)
  zr_heap_slow_update()
  Machine.value(QNIL)
end

sig [] => Value
machine def zr_alloc_trace_clear
  t = zr_alloc_trace()
  if AllocTrace.rows(t) != 0
    zr_xfree(AllocTrace.rows(t))
  end
  AllocTrace.set_rows(t, 0)
  AllocTrace.set_capa(t, 0)
  AllocTrace.set_used(t, 0)
  Machine.value(QNIL)
end

# Returns `[file, line, class path, method id, generation]` for a traced
# object, or nil.
sig [Value] => Value
machine def zr_alloc_trace_info(v)
  row = zr_alloc_trace_row(v)
  if row == 0
    return Machine.value(QNIL)
  end
  out = zr_ary_new(5)
  zr_ary_push(out, zr_str_new(AllocRow.file(row), AllocRow.file_len(row)))
  zr_ary_push(out, zr_fix(AllocRow.line(row)))
  meta = AllocRow.meta(row)
  if meta != 0 && !zr_special_p(FrameMeta.owner(meta))
    zr_ary_push(out, zr_class_path(FrameMeta.owner(meta)))
    zr_ary_push(out, zr_sym(FrameMeta.name(meta)))
  else
    zr_ary_push(out, Machine.value(QNIL))
    zr_ary_push(out, Machine.value(QNIL))
  end
  zr_ary_push(out, zr_fix(AllocRow.generation(row)))
  out
end
