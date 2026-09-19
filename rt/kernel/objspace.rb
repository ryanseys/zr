# ObjectSpace's view of the heap: the objects a walk yields, the census
# by type, the object an id names, and what one object refers to. A walk
# copies what it finds into an Array before any Ruby runs, as gc.c's
# os_obj_of does, so a block that allocates never meets a cell it made.

# Whether cell `v` is an object a program can hold, as internal_object_p
# decides: not one of the runtime's own records, not a hidden object, and
# not the singleton class of a class while that singleton class has no
# singleton class of its own.
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
  if t == T_CLASS && (RBasic.flags(v) & FL_SINGLETON) != 0
    attached = RClass.attached(v)
    if !zr_special_p(attached) && (RBasic.flags(attached) & T_MASK) == T_CLASS
      return (RBasic.flags(klass) & FL_SINGLETON) != 0 && RClass.attached(klass) == v
    end
  end
  true
end

# Every live object a program can hold, of `mod` when it is not nil.
sig [Value] => Value
machine def zr_objspace_objects(mod)
  out = zr_ary_new(1024)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = 0
    while i < ArenaHead.ncells(base)
      v = Machine.value(first + (i * bytes))
      if (RBasic.flags(v) & FL_ALLOCATED) != 0 && Machine.word(v) != Machine.word(out) && zr_objspace_visible_p(v)
        if mod == QNIL || zr_is_a(v, mod)
          zr_ary_push(out, v)
        end
      end
      i += 1
    end
    a += 1
  end
  out
end

# The heap by type: the cells in all, the free ones, then the live cells
# of each of the 32 type tags.
sig [] => Value
machine def zr_objspace_census
  counts = Machine.slot(32 * 8)
  memset(counts, Machine.i32(0), 32 * 8)
  free_cells = 0
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = 0
    while i < ArenaHead.ncells(base)
      flags = Machine.load64(first + (i * bytes), 0)
      if (flags & FL_ALLOCATED) == 0
        free_cells += 1
      else
        slot = counts + ((flags & T_MASK) * 8)
        Machine.store64(slot, 0, Machine.load64(slot, 0) + 1)
      end
      i += 1
    end
    a += 1
  end
  out = zr_ary_new(34)
  zr_ary_push(out, zr_fix(zr_heap_cells()))
  zr_ary_push(out, zr_fix(free_cells))
  t = 0
  while t < 32
    zr_ary_push(out, zr_fix(Machine.load64(counts + (t * 8), 0)))
    t += 1
  end
  out
end

# The live object whose object_id is `id`, or nil: only an object that
# was asked for its id has one.
sig [Value] => Value
machine def zr_objspace_id2ref(id)
  a = 0
  while a < Heap.arenas(zr_heap())
    base = zr_arena_at(a)
    first = zr_arena_first(base)
    bytes = ArenaHead.cell(base)
    i = 0
    while i < ArenaHead.ncells(base)
      v = Machine.value(first + (i * bytes))
      if (RBasic.flags(v) & FL_ALLOCATED) != 0 && zr_objspace_visible_p(v)
        t = zr_ivtab(v)
        if t != 0 && zr_ivtab_get(t, Machine.id(:__object_id__)) == id
          return v
        end
      end
      i += 1
    end
    a += 1
  end
  Machine.value(QNIL)
end

# What `v` refers to, as the collector reads it: its class, then its
# children in the order they are marked, each once. Marking them queues
# them on the mark stack, where they are read back and unmarked; no cell
# is marked outside a collection, so every child is new to the stack.
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

# The bytes `v` holds: its cell, and the buffer a String, an Array or a
# Hash keeps outside it. An immediate holds none.
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

# ObjectSpace.trace_object_allocations: where each cell allocated while
# tracing is on was made. The rows live outside the heap, keyed by the
# cell's address, so recording one allocates no cell; a cell's row goes
# when the cell is freed.
Machine.struct :AllocTrace, rows: Ptr, capa: Word, used: Word, on: Word
# `meta` is the C method the cell was made in, or 0 when Ruby made it.
Machine.struct :AllocRow, cell: Word, file: Ptr, file_len: Word, line: Word, meta: Ptr, generation: Word
# A row whose cell was freed, which a probe passes over.
ALLOC_GONE = 1

sig [] => Ptr
machine def zr_alloc_trace
  Machine.static(:alloc_trace, AllocTrace.size)
end

# The row for `cell`, or the free row a new one goes in. Half the table
# at most holds rows, freed ones counted, so a probe meets an empty row.
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

# Room for one more row: the table doubles, leaving its freed rows out,
# once half of it is taken.
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

# `cell` was just made: the file and line of the Ruby frame on top, and
# the C method it was made in when the top frame is one.
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

# A freed cell loses its row.
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

# `[file, line, class path, method id, generation]` for a traced object,
# or nil.
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
