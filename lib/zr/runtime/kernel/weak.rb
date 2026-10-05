module Zr::Kern
  # Weak tables: Hashes whose entries the collector does not keep alive.
  # `FL_WEAK` makes keys and values weak (ObjectSpace::WeakMap).
  # `FL_WEAKKEY` makes only keys weak (ObjectSpace::WeakKeyMap, and the
  # finalizer table). A static list refers to the tables but does not
  # mark them. After marking, each live table removes the entries whose
  # weak key or value is dead. A dead key of the finalizer table queues
  # its procs.
  FL_WEAK = 1 << 19
  FL_WEAKKEY = 1 << 20
  WEAK_BOTH = 1
  WEAK_KEY = 2
  G_FINALIZERS = 45

  class WeakList < Layout
    attr_accessor :ptr #: ptr
    attr_accessor :len #: word
    attr_accessor :capa #: word
  end

  #: () -> ptr
  def zr_weak_list
    Machine.static(:weak_list, WeakList.size)
  end

  #: () -> ptr
  def zr_finalizer_queue
    Machine.static(:finalizer_queue, WeakList.size)
  end

  #: (ptr, value) -> void
  def zr_weak_list_push(l, v)
    n = WeakList[l].len
    if n == WeakList[l].capa
      capa = n < 4 ? 8 : n * 2
      p = zr_xmalloc(capa * 8)
      if WeakList[l].ptr != 0
        zr_memcpy(p, WeakList[l].ptr, n * 8)
        zr_xfree(WeakList[l].ptr)
      end
      WeakList[l].ptr = p
      WeakList[l].capa = capa
    end
    Machine.store64(WeakList[l].ptr + (n * 8), 0, Machine.word(v))
    WeakList[l].len = n + 1
  end

  # Makes a new weak table. `kind` is WEAK_BOTH or WEAK_KEY. If `identity`
  # is set, the table compares keys by identity, else by `eql?`.
  #: (word, bool) -> value
  def zr_weak_table_new(kind, identity)
    h = zr_hash_new()
    flags = RBasic[h].flags | (kind == WEAK_BOTH ? FL_WEAK : FL_WEAKKEY)
    if identity
      flags = flags | FL_IDENTITY
    end
    RBasic[h].flags = flags
    zr_weak_list_push(zr_weak_list(), h)
    h
  end

  #: (value, value) -> value
  def zr_weak_table_new_m(kind, identity)
    zr_weak_table_new(zr_fix2long(kind), identity != QFALSE && identity != QNIL)
  end

  #: (value) -> bool
  def zr_dead_p(v)
    !zr_special_p(v) && (RBasic[v].flags & FL_STACK) == 0 && !zr_marked_p(v)
  end

  # Runs after marking. The live tables stay in the list, and they lose
  # the entries whose weak key or value is not marked.
  #: () -> void
  def zr_weak_prune
    l = zr_weak_list()
    finalizers = zr_global(G_FINALIZERS)
    i = 0
    kept = 0
    while i < WeakList[l].len
      h = Machine.value(Machine.load64(WeakList[l].ptr + (i * 8), 0))
      i += 1
      if !zr_dead_p(h)
        Machine.store64(WeakList[l].ptr + (kept * 8), 0, Machine.word(h))
        kept += 1
        zr_weak_prune_table(h, h == finalizers)
      end
    end
    WeakList[l].len = kept
  end

  #: (value, bool) -> void
  def zr_weak_prune_table(h, finalizer)
    both = (RBasic[h].flags & FL_WEAK) != 0
    n = RHash[h].len
    i = 0
    while i < n
      e = RHash[h].entries + (i * HEntry.size)
      if HEntry[e].live != 0 && (zr_dead_p(HEntry[e].key) || (both && zr_dead_p(HEntry[e].value)))
        if finalizer
          zr_weak_list_push(zr_finalizer_queue(), HEntry[e].value)
          # It runs at the next safe point.
          zr_poll_set()
        end
        HEntry[e].live = 0
        HEntry[e].key = Machine.value(QNIL)
        HEntry[e].value = Machine.value(QNIL)
        RHash[h].live = RHash[h].live - 1
      end
      i += 1
    end
  end

  # The queued finalizer entries are roots until they run.
  #: () -> void
  def zr_mark_finalizer_queue
    q = zr_finalizer_queue()
    i = 0
    while i < WeakList[q].len
      zr_mark(Machine.value(Machine.load64(WeakList[q].ptr + (i * 8), 0)))
      i += 1
    end
  end

  # rb_gc_copy_finalizer: a dup or a clone gets the original's
  # finalizers, under its own id. The table compares by identity, so
  # the lookup runs no Ruby code.
  #: (value, value) -> void
  def zr_copy_finalizers(copy, orig)
    t = zr_global(G_FINALIZERS)
    if zr_special_p(t) || RHash[t].live == 0
      return
    end
    e = zr_hash_entry(t, orig)
    if e == 0 || e == HASH_RAISED
      return
    end
    row = HEntry[e].value
    n = RArray[row].len
    fresh = zr_ary_new(n)
    zr_ary_push(fresh, zr_obj_object_id(copy, 0, 0, Machine.value(QNIL), Machine.value(QNIL)))
    i = 1
    while i < n
      zr_ary_push(fresh, Machine.value(Machine.load64(RArray[row].ptr + (i * 8), 0)))
      i += 1
    end
    zr_hash_store(t, copy, fresh)
  end

  # The finalizer table: object => [object_id, proc, ...], with weak keys.
  #: () -> value
  def zr_finalizers
    t = zr_global(G_FINALIZERS)
    if zr_special_p(t)
      t = zr_weak_table_new(WEAK_KEY, true)
      zr_set_global(G_FINALIZERS, t)
    end
    t
  end

  #: () -> value
  def zr_finalizers_m
    zr_finalizers()
  end

  # Runs the queued finalizers. It calls each proc with its object's id.
  # If a proc raises, it prints the error and continues. It runs after a
  # collection that the program requests, and at the next poll after
  # other collections. It never runs inside an allocation.
  # The queue runs in the order the objects were found, first in first
  # out, as ruby runs its finalizers.
  #: () -> value
  def zr_finalizers_run
    q = zr_finalizer_queue()
    while WeakList[q].len > 0
      row = Machine.value(Machine.load64(WeakList[q].ptr, 0))
      n = WeakList[q].len - 1
      i = 0
      while i < n
        Machine.store64(WeakList[q].ptr + (i * 8), 0, Machine.load64(WeakList[q].ptr + ((i + 1) * 8), 0))
        i += 1
      end
      WeakList[q].len = n
      r = zr_finalizer_row_run(row)
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  # A proc that raises gets ruby's warning, `prog: warning: Exception in
  # finalizer #<Proc...>` (unless $VERBOSE is nil), then its error.
  #: (value) -> value
  def zr_finalizer_row_run(row)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_ary_at(row, 0)))
    i = 1
    while i < RArray[row].len
      r = zr_send(zr_ary_at(row, i), Machine.id(:call), 1, slot)
      if r == QUNDEF
        raised = Task[zr_task()].pending
        Task[zr_task()].pending = Machine.value(QNIL)
        if zr_gvar_get(Machine.id(:$VERBOSE)) != QNIL
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_str(b, zr_gvar_get(Machine.id(:$0)))
          zr_buf_push(b, Machine.bytes(": warning: Exception in finalizer "), 34)
          shown = zr_inspect(zr_ary_at(row, i))
          if shown != QUNDEF
            zr_buf_str(b, shown)
          end
          zr_buf_byte(b, 10)
          zr_warning_write(zr_buf_take(b))
        end
        zr_error_print(raised)
      end
      i += 1
    end
    Machine.value(QNIL)
  end

  # At the end of the program, each finalizer that is still registered
  # runs, in registration order.
  #: () -> void
  def zr_finalizers_at_exit
    t = zr_global(G_FINALIZERS)
    if zr_special_p(t)
      return
    end
    n = RHash[t].len
    i = 0
    while i < n
      e = RHash[t].entries + (i * HEntry.size)
      if HEntry[e].live != 0
        row = HEntry[e].value
        HEntry[e].live = 0
        RHash[t].live = RHash[t].live - 1
        zr_finalizer_row_run(row)
      end
      i += 1
    end
  end
end
