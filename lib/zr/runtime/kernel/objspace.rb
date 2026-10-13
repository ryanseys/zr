# ObjectSpace's view of the heap: the objects that a walk yields, the
# count by type, the object for an id, and the objects that one object
# refers to. A walk copies the objects it finds into an Array before any
# Ruby code runs, as gc.c's os_obj_of does. Thus a block that allocates
# never sees a cell that it made.

module Zr::Kern
  # Whether cell `v` is an object that a program can get, as
  # internal_object_p decides. It is not a runtime record, not a hidden
  # object, and not the singleton class of a class while that singleton
  # class has no singleton class of its own.
  #: (value) -> bool
  def zr_objspace_visible_p(v)
    t = RBasic[v].flags & T_MASK
    if t == T_NONE || t == T_CREF || t == T_ENV || t == T_ICLASS
      return false
    end
    klass = RBasic[v].klass
    if Machine.word(klass) == 0 || zr_special_p(klass)
      return false
    end
    if (RBasic[v].flags & FL_CONCEALED) != 0 || (RBasic[klass].flags & FL_CONCEALED) != 0
      return false
    end
    if t == T_CLASS && (RBasic[v].flags & FL_SINGLETON) != 0
      attached = RClass[v].attached
      if !zr_special_p(attached) && (RBasic[attached].flags & T_MASK) == T_CLASS
        return (RBasic[klass].flags & FL_SINGLETON) != 0 && RClass[klass].attached == v
      end
    end
    true
  end

  # All live objects that a program can get, only of `mod` if it is not nil.
  # A major collection runs first: a dead cell that a minor collection left
  # can point at a cell that a later one freed, and the walk must not give
  # it back to the program.
  #: (value) -> value
  def zr_objspace_objects(mod)
    zr_collect_kind(SIZE_CLASSES, true)
    out = zr_ary_new(1024)
    a = 0
    while a < Heap[zr_heap()].arenas
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead[base].cell
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

  # `ObjectSpace.count_objects(result)`: stores in `result` the total
  # cells, the free cells and the live cells of each kind, under CRuby's
  # names, in CRuby's order, leaving out a kind with none. It makes no
  # object, so two counts around some code differ only by what that code
  # made. The caller has emptied `result`.
  #: (value) -> value
  def zr_objspace_count_into(result)
    counts = Machine.slot(32 * 8)
    total = zr_objspace_tally(counts)
    zr_hash_store(result, zr_sym(Machine.id(:TOTAL)), zr_fix(zr_heap_cells()))
    zr_hash_store(result, zr_sym(Machine.id(:FREE)), zr_fix(zr_heap_cells() - total))
    # This runtime gives a tag of its own to some objects that CRuby keeps
    # as one of its types: a Proc, a Method and a Fiber count as T_DATA,
    # a cref and an env as T_IMEMO, and a tag with no CRuby name (an
    # exception's) as T_OBJECT.
    named = 0
    t = 0
    while t < 32
      if t == T_CLASS || t == T_MODULE || t == T_FLOAT || t == T_STRING || t == T_REGEXP || t == T_ARRAY || t == T_HASH ||
         t == T_BIGNUM || t == T_PROC || t == T_METHOD || t == T_FIBER || t == T_DATA || t == T_CREF || t == T_ENV || t == T_ICLASS ||
         t == T_FILE
        named += Machine.load64(counts + (t * 8), 0)
      end
      t += 1
    end
    objects = total - named
    zr_census_store(result, Machine.id(:T_OBJECT), objects)
    zr_census_store(result, Machine.id(:T_CLASS), Machine.load64(counts + (T_CLASS * 8), 0))
    zr_census_store(result, Machine.id(:T_MODULE), Machine.load64(counts + (T_MODULE * 8), 0))
    zr_census_store(result, Machine.id(:T_FLOAT), Machine.load64(counts + (T_FLOAT * 8), 0))
    zr_census_store(result, Machine.id(:T_STRING), Machine.load64(counts + (T_STRING * 8), 0))
    zr_census_store(result, Machine.id(:T_REGEXP), Machine.load64(counts + (T_REGEXP * 8), 0))
    zr_census_store(result, Machine.id(:T_ARRAY), Machine.load64(counts + (T_ARRAY * 8), 0))
    zr_census_store(result, Machine.id(:T_HASH), Machine.load64(counts + (T_HASH * 8), 0))
    zr_census_store(result, Machine.id(:T_BIGNUM), Machine.load64(counts + (T_BIGNUM * 8), 0))
    zr_census_store(result, Machine.id(:T_DATA), Machine.load64(counts + (T_DATA * 8), 0) + Machine.load64(counts + (T_PROC * 8), 0) + Machine.load64(counts + (T_METHOD * 8), 0) + Machine.load64(counts + (T_FIBER * 8), 0))
    zr_census_store(result, Machine.id(:T_IMEMO), Machine.load64(counts + (T_CREF * 8), 0) + Machine.load64(counts + (T_ENV * 8), 0))
    zr_census_store(result, Machine.id(:T_ICLASS), Machine.load64(counts + (T_ICLASS * 8), 0))
    result
  end

  #: (value, word, word) -> void
  def zr_census_store(result, id, n)
    if n > 0
      zr_hash_store(result, zr_sym(id), zr_fix(n))
    end
  end

  # Counts the live cells of each of the 32 type tags into `counts`, and
  # returns the number of live cells.
  #: (ptr) -> word
  def zr_objspace_tally(counts)
    Libc.memset(counts, Machine.i32(0), 32 * 8)
    live_cells = 0
    a = 0
    while a < Heap[zr_heap()].arenas
      base = zr_arena_at(a)
      first = zr_arena_first(base)
      bytes = ArenaHead[base].cell
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
    live_cells
  end

  # The heap by type: the total cells, the free cells, then the live cells
  # of each of the 32 type tags.
  #: () -> value
  def zr_objspace_census
    counts = Machine.slot(32 * 8)
    # The result is made before the tally, which counts it.
    out = zr_ary_new(34)
    live_cells = zr_objspace_tally(counts)
    zr_ary_push(out, zr_fix(zr_heap_cells()))
    zr_ary_push(out, zr_fix(zr_heap_cells() - live_cells))
    t = 0
    while t < 32
      zr_ary_push(out, zr_fix(Machine.load64(counts + (t * 8), 0)))
      t += 1
    end
    out
  end

  # The objects that `v` refers to, as the collector reads them: its class,
  # then its children in mark order, each one time. The mark puts them on
  # the mark stack, where this code reads them and clears their marks. No
  # cell is marked outside a collection, so each child is new to the
  # stack.
  #: (value) -> value
  def zr_objspace_reachable(v)
    out = zr_ary_new(8)
    if zr_special_p(v)
      return out
    end
    s = zr_mark_stack()
    from = MarkStack[s].len
    Machine.store64(zr_mark_every(), 0, 1)
    zr_mark(RBasic[v].klass)
    zr_mark_children(v)
    if (RBasic[v].flags & FL_EXIVAR) != 0
      zr_mark_ivtab(zr_exivar_tab(v))
    end
    Machine.store64(zr_mark_every(), 0, 0)
    i = from
    while i < MarkStack[s].len
      child = Machine.value(Machine.load64(MarkStack[s].ptr + (i * 8), 0))
      zr_mark_unset(child)
      if zr_objspace_visible_p(child)
        zr_ary_push(out, child)
      end
      i += 1
    end
    MarkStack[s].len = from
    out
  end

  # The objects that the collector's roots reach first, by the kind of
  # root, as ObjectSpace.reachable_objects_from_root groups them: the
  # runtime's roots (its classes and the main object), the global
  # variables, the objects in the running fibers and the kernel's frames,
  # and the finalizers. This makes each cell of the result before the
  # first mark, because a collection must not start while this walk owns
  # the marks.
  #: () -> value
  def zr_objspace_roots
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
    from = MarkStack[s].len
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
  #: (ptr, word, value, value) -> void
  def zr_objspace_take(s, from, into, out)
    i = from
    while i < MarkStack[s].len
      child = Machine.value(Machine.load64(MarkStack[s].ptr + (i * 8), 0))
      zr_mark_unset(child)
      if zr_objspace_visible_p(child) && child != out && !zr_objspace_row_p(out, child)
        zr_ary_push(into, child)
      end
      i += 1
    end
    MarkStack[s].len = from
  end

  # Whether `v` is one of the keys or values of the result `out`.
  #: (value, value) -> bool
  def zr_objspace_row_p(out, v)
    i = 0
    while i < RHash[out].len
      e = RHash[out].entries + (i * HEntry.size)
      if HEntry[e].key == v || HEntry[e].value == v
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
  #: (value) -> value
  def zr_objspace_super(klass)
    s = RClass[klass].superclass
    if Machine.word(s) == 0 || s == QNIL
      return Machine.value(QNIL)
    end
    if zr_type(s) == T_ICLASS
      return zr_fix(Machine.word(s))
    end
    s
  end

  # The facts about `v`'s cell that ObjectSpace.dump writes, as bits:
  # DUMP_EMBEDDED when a String, an Array or an object keeps its contents
  # in the cell, DUMP_FSTRING for a String in the fstring table,
  # DUMP_CHILLED for a chilled String, and DUMP_OLD when the cell lived
  # through a collection.
  DUMP_EMBEDDED = 1
  DUMP_FSTRING = 2
  DUMP_CHILLED = 4
  DUMP_OLD = 8

  #: (value) -> value
  def zr_objspace_dump_bits(v)
    if zr_special_p(v)
      return zr_fix(0)
    end
    t = RBasic[v].flags & T_MASK
    bits = zr_old_p(v) ? DUMP_OLD : 0
    if t == T_STRING
      bits = bits | (zr_str_embedded_p(v) ? DUMP_EMBEDDED : 0)
      bits = bits | ((RBasic[v].flags & FL_FSTR) != 0 ? DUMP_FSTRING : 0)
      bits = bits | (zr_str_chilled_p(v) ? DUMP_CHILLED : 0)
    elsif t == T_ARRAY
      bits = bits | (zr_ary_embedded_p(v) ? DUMP_EMBEDDED : 0)
    elsif t == T_OBJECT || t == T_BIGNUM
      bits = bits | (zr_ivtab_embedded_p(Machine.ptr(RObject[v].iv)) ? DUMP_EMBEDDED : 0)
    end
    zr_fix(bits)
  end

  # The bytes that String `s` has room for, not counting the NUL.
  #: (value) -> value
  def zr_objspace_str_capa(s)
    zr_fix(RString[s].capa)
  end

  # The address of `v`'s cell, which ObjectSpace.dump writes.
  #: (value) -> value
  def zr_objspace_address(v)
    zr_fix(Machine.word(v))
  end

  # The size of `v`'s cell, which ObjectSpace.dump calls its slot size.
  #: (value) -> value
  def zr_objspace_slot_size(v)
    zr_special_p(v) ? zr_fix(0) : zr_fix(zr_cell_bytes(v))
  end

  # The bytes that `v` uses: its cell, and the buffer that a String, an
  # Array or a Hash keeps outside the cell. An immediate uses none.
  #: (value) -> value
  def zr_objspace_memsize(v)
    if zr_special_p(v)
      return zr_fix(0)
    end
    t = RBasic[v].flags & T_MASK
    n = zr_cell_bytes(v)
    if t == T_STRING
      n += zr_str_embedded_p(v) ? 0 : zr_str_gap(v) + RString[v].capa + 1
    elsif t == T_ARRAY
      n += zr_ary_embedded_p(v) ? 0 : RArray[v].capa * 8
    elsif t == T_HASH
      n += (RHash[v].cap * HEntry.size) + (RHash[v].nbins * 8)
    elsif t == T_OBJECT || t == T_BIGNUM
      iv = Machine.ptr(RObject[v].iv)
      n += zr_ivtab_embedded_p(iv) ? 0 : IvTab[iv].cap * IvEntry.size
    end
    zr_fix(n)
  end

  # ObjectSpace.trace_object_allocations: the source location of each cell
  # allocated while tracing is on. The records are outside the heap, with
  # the cell's address as the key, so a record allocates no cell. The
  # record of a cell goes away when the cell is freed.
  class AllocTrace < Layout
    attr_accessor :rows #: ptr
    attr_accessor :capa #: word
    attr_accessor :used #: word
    attr_accessor :on #: word
  end
  # `meta` is the C method that made the cell, or 0 if Ruby code made it.
  class AllocRow < Layout
    attr_accessor :cell #: word
    attr_accessor :file #: ptr
    attr_accessor :file_len #: word
    attr_accessor :line #: word
    attr_accessor :meta #: ptr
    attr_accessor :generation #: word
  end
  # Marks a record whose cell was freed. A probe skips it.
  ALLOC_GONE = 1

  #: () -> ptr
  def zr_alloc_trace
    Machine.static(:alloc_trace, AllocTrace.size)
  end

  # The record for `cell`, or the free record for a new one. At most half
  # of the table contains records, freed ones included, so a probe always
  # finds an empty record.
  #: (ptr, word) -> ptr
  def zr_alloc_trace_probe(t, cell)
    mask = AllocTrace[t].capa - 1
    i = Machine.mul_wrap(cell / CELL_MIN, 2654435761) & mask
    row = AllocTrace[t].rows + (i * AllocRow.size)
    free_row = 0
    while AllocRow[row].cell != cell && AllocRow[row].cell != 0
      if AllocRow[row].cell == ALLOC_GONE && free_row == 0
        free_row = row
      end
      i = (i + 1) & mask
      row = AllocTrace[t].rows + (i * AllocRow.size)
    end
    if AllocRow[row].cell == 0 && free_row != 0
      return free_row
    end
    row
  end

  # Makes space for one more record. When half of the table is used, the
  # table doubles, and it does not copy the freed records.
  #: (ptr) -> void
  def zr_alloc_trace_room(t)
    if (AllocTrace[t].used + 1) * 2 <= AllocTrace[t].capa
      return
    end
    old = AllocTrace[t].rows
    old_capa = AllocTrace[t].capa
    capa = old_capa == 0 ? 1024 : old_capa * 2
    AllocTrace[t].rows = zr_xmalloc(capa * AllocRow.size)
    Libc.memset(AllocTrace[t].rows, Machine.i32(0), capa * AllocRow.size)
    AllocTrace[t].capa = capa
    AllocTrace[t].used = 0
    i = 0
    while i < old_capa
      row = old + (i * AllocRow.size)
      if AllocRow[row].cell > ALLOC_GONE
        zr_memcpy(zr_alloc_trace_probe(t, AllocRow[row].cell), row, AllocRow.size)
        AllocTrace[t].used = AllocTrace[t].used + 1
      end
      i += 1
    end
    if old != 0
      zr_xfree(old)
    end
  end

  # Records a new `cell`: the file and line of the top Ruby frame, and the
  # method that runs: the C method that made it, or else the method of the
  # Ruby frame (rb_tracearg_method_id), none at the top level.
  #: (ptr) -> void
  def zr_alloc_trace_record(cell)
    top = Task[zr_task()].top
    rec = zr_frame_with_file(top)
    if rec == 0
      return
    end
    t = zr_alloc_trace()
    zr_alloc_trace_room(t)
    row = zr_alloc_trace_probe(t, cell)
    if AllocRow[row].cell != cell
      AllocTrace[t].used = AllocTrace[t].used + 1
    end
    meta = Frame[rec].meta
    AllocRow[row].cell = cell
    AllocRow[row].file = FrameMeta[meta].file
    AllocRow[row].file_len = FrameMeta[meta].file_len
    AllocRow[row].line = zr_frame_line(rec)
    AllocRow[row].meta = zr_method_meta_of(top)
    AllocRow[row].generation = Heap[zr_heap()].collections
  end

  # Removes the record of a freed cell.
  #: (ptr) -> void
  def zr_alloc_trace_forget(cell)
    t = zr_alloc_trace()
    row = zr_alloc_trace_probe(t, cell)
    if AllocRow[row].cell == cell
      AllocRow[row].cell = ALLOC_GONE
    end
  end

  #: (value) -> ptr
  def zr_alloc_trace_row(v)
    t = zr_alloc_trace()
    if zr_special_p(v) || AllocTrace[t].used == 0
      return 0
    end
    row = zr_alloc_trace_probe(t, Machine.word(v))
    AllocRow[row].cell == Machine.word(v) ? row : 0
  end

  #: (value) -> value
  def zr_alloc_trace_set(on)
    AllocTrace[zr_alloc_trace()].on = on == QTRUE ? 1 : 0
    zr_heap_slow_update()
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_alloc_trace_clear
    t = zr_alloc_trace()
    if AllocTrace[t].rows != 0
      zr_xfree(AllocTrace[t].rows)
    end
    AllocTrace[t].rows = 0
    AllocTrace[t].capa = 0
    AllocTrace[t].used = 0
    Machine.value(QNIL)
  end

  # Returns `[file, line, class path, method id, generation]` for a traced
  # object, or nil.
  #: (value) -> value
  def zr_alloc_trace_info(v)
    row = zr_alloc_trace_row(v)
    if row == 0
      return Machine.value(QNIL)
    end
    out = zr_ary_new(5)
    zr_ary_push(out, zr_str_new(AllocRow[row].file, AllocRow[row].file_len))
    zr_ary_push(out, zr_fix(AllocRow[row].line))
    meta = AllocRow[row].meta
    if meta != 0 && !zr_special_p(FrameMeta[meta].owner)
      zr_ary_push(out, zr_alloc_class_path(FrameMeta[meta].owner))
      zr_ary_push(out, zr_sym(FrameMeta[meta].name))
    else
      zr_ary_push(out, Machine.value(QNIL))
      zr_ary_push(out, Machine.value(QNIL))
    end
    zr_ary_push(out, zr_fix(AllocRow[row].generation))
    out
  end

  # The name of the class that owns the method, as the tracer keeps it: an
  # anonymous class, a singleton class and a frozen class give nil.
  #: (value) -> value
  def zr_alloc_class_path(owner)
    if (RBasic[owner].flags & FL_FREEZE) != 0
      return Machine.value(QNIL)
    end
    RClass[owner].name
  end

  # Keeps a helper class of the core library out of ObjectSpace and out of
  # Class#subclasses, as a class that the eval support makes is kept: ruby
  # writes these helpers in C.
  #: (value) -> value
  def zr_class_conceal_m(klass)
    RBasic[klass].flags = RBasic[klass].flags | FL_CONCEALED
    klass
  end
end
