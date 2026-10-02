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

  WeakList = layout ptr: Ptr, len: Word, capa: Word

  sig [] => Ptr
  def zr_weak_list
    Machine.static(:weak_list, WeakList.size)
  end

  sig [] => Ptr
  def zr_finalizer_queue
    Machine.static(:finalizer_queue, WeakList.size)
  end

  sig [Ptr, Value] => Void
  def zr_weak_list_push(l, v)
    n = WeakList.len(l)
    if n == WeakList.capa(l)
      capa = n < 4 ? 8 : n * 2
      p = zr_xmalloc(capa * 8)
      if WeakList.ptr(l) != 0
        zr_memcpy(p, WeakList.ptr(l), n * 8)
        zr_xfree(WeakList.ptr(l))
      end
      WeakList.set_ptr(l, p)
      WeakList.set_capa(l, capa)
    end
    Machine.store64(WeakList.ptr(l) + (n * 8), 0, Machine.word(v))
    WeakList.set_len(l, n + 1)
  end

  # Makes a new weak table. `kind` is WEAK_BOTH or WEAK_KEY. If `identity`
  # is set, the table compares keys by identity, else by `eql?`.
  sig [Word, Bool] => Value
  def zr_weak_table_new(kind, identity)
    h = zr_hash_new()
    flags = RBasic.flags(h) | (kind == WEAK_BOTH ? FL_WEAK : FL_WEAKKEY)
    if identity
      flags = flags | FL_IDENTITY
    end
    RBasic.set_flags(h, flags)
    zr_weak_list_push(zr_weak_list(), h)
    h
  end

  sig [Value, Value] => Value
  def zr_weak_table_new_m(kind, identity)
    zr_weak_table_new(zr_fix2long(kind), identity != QFALSE && identity != QNIL)
  end

  sig [Value] => Bool
  def zr_dead_p(v)
    !zr_special_p(v) && (RBasic.flags(v) & FL_STACK) == 0 && !zr_marked_p(v)
  end

  # Runs after marking. The live tables stay in the list, and they lose
  # the entries whose weak key or value is not marked.
  sig [] => Void
  def zr_weak_prune
    l = zr_weak_list()
    finalizers = zr_global(G_FINALIZERS)
    i = 0
    kept = 0
    while i < WeakList.len(l)
      h = Machine.value(Machine.load64(WeakList.ptr(l) + (i * 8), 0))
      i += 1
      if !zr_dead_p(h)
        Machine.store64(WeakList.ptr(l) + (kept * 8), 0, Machine.word(h))
        kept += 1
        zr_weak_prune_table(h, h == finalizers)
      end
    end
    WeakList.set_len(l, kept)
  end

  sig [Value, Bool] => Void
  def zr_weak_prune_table(h, finalizer)
    both = (RBasic.flags(h) & FL_WEAK) != 0
    n = RHash.len(h)
    i = 0
    while i < n
      e = RHash.entries(h) + (i * HEntry.size)
      if HEntry.live(e) != 0 && (zr_dead_p(HEntry.key(e)) || (both && zr_dead_p(HEntry.value(e))))
        if finalizer
          zr_weak_list_push(zr_finalizer_queue(), HEntry.value(e))
          # It runs at the next safe point.
          zr_poll_set()
        end
        HEntry.set_live(e, 0)
        HEntry.set_key(e, Machine.value(QNIL))
        HEntry.set_value(e, Machine.value(QNIL))
        RHash.set_live(h, RHash.live(h) - 1)
      end
      i += 1
    end
  end

  # The queued finalizer entries are roots until they run.
  sig [] => Void
  def zr_mark_finalizer_queue
    q = zr_finalizer_queue()
    i = 0
    while i < WeakList.len(q)
      zr_mark(Machine.value(Machine.load64(WeakList.ptr(q) + (i * 8), 0)))
      i += 1
    end
  end

  # The finalizer table: object => [object_id, proc, ...], with weak keys.
  sig [] => Value
  def zr_finalizers
    t = zr_global(G_FINALIZERS)
    if zr_special_p(t)
      t = zr_weak_table_new(WEAK_KEY, true)
      zr_set_global(G_FINALIZERS, t)
    end
    t
  end

  sig [] => Value
  def zr_finalizers_m
    zr_finalizers()
  end

  # Runs the queued finalizers. It calls each proc with its object's id.
  # If a proc raises, it prints the error and continues. It runs after a
  # collection that the program requests, and at the next poll after
  # other collections. It never runs inside an allocation.
  # The queue runs in the order the objects were found, first in first
  # out, as ruby runs its finalizers.
  sig [] => Value
  def zr_finalizers_run
    q = zr_finalizer_queue()
    while WeakList.len(q) > 0
      row = Machine.value(Machine.load64(WeakList.ptr(q), 0))
      n = WeakList.len(q) - 1
      i = 0
      while i < n
        Machine.store64(WeakList.ptr(q) + (i * 8), 0, Machine.load64(WeakList.ptr(q) + ((i + 1) * 8), 0))
        i += 1
      end
      WeakList.set_len(q, n)
      r = zr_finalizer_row_run(row)
      return r if r == QUNDEF
    end
    Machine.value(QNIL)
  end

  # A proc that raises gets ruby's warning, `prog: warning: Exception in
  # finalizer #<Proc...>` (unless $VERBOSE is nil), then its error.
  sig [Value] => Value
  def zr_finalizer_row_run(row)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(zr_ary_at(row, 0)))
    i = 1
    while i < RArray.len(row)
      r = zr_send(zr_ary_at(row, i), Machine.id(:call), 1, slot)
      if r == QUNDEF
        raised = Task.pending(zr_task())
        Task.set_pending(zr_task(), Machine.value(QNIL))
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
  sig [] => Void
  def zr_finalizers_at_exit
    t = zr_global(G_FINALIZERS)
    if zr_special_p(t)
      return
    end
    n = RHash.len(t)
    i = 0
    while i < n
      e = RHash.entries(t) + (i * HEntry.size)
      if HEntry.live(e) != 0
        row = HEntry.value(e)
        HEntry.set_live(e, 0)
        RHash.set_live(t, RHash.live(t) - 1)
        zr_finalizer_row_run(row)
      end
      i += 1
    end
  end
end
