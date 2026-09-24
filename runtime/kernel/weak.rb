# Weak tables: Hashes whose entries the collector does not keep alive.
# `FL_WEAK` holds keys and values weakly (ObjectSpace::WeakMap);
# `FL_WEAKKEY` keys only (ObjectSpace::WeakKeyMap, and the finalizer
# table). A static list names the tables without marking them; after
# marking, each table still alive loses the entries whose weak side
# died, and a dead key of the finalizer table queues its procs.
FL_WEAK = 1 << 19
FL_WEAKKEY = 1 << 20
WEAK_BOTH = 1
WEAK_KEY = 2
G_FINALIZERS = 45

Machine.struct :WeakList, ptr: Ptr, len: Word, capa: Word

sig [] => Ptr
machine def zr_weak_list
  Machine.static(:weak_list, WeakList.size)
end

sig [] => Ptr
machine def zr_finalizer_queue
  Machine.static(:finalizer_queue, WeakList.size)
end

sig [Ptr, Value] => Void
machine def zr_weak_list_push(l, v)
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

# A fresh weak table: `kind` WEAK_BOTH or WEAK_KEY; `identity` compares
# keys by identity, else by `eql?`.
sig [Word, Bool] => Value
machine def zr_weak_table_new(kind, identity)
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
machine def zr_weak_table_new_m(kind, identity)
  zr_weak_table_new(zr_fix2long(kind), identity != QFALSE && identity != QNIL)
end

sig [Value] => Bool
machine def zr_dead_p(v)
  !zr_special_p(v) && (RBasic.flags(v) & FL_STACK) == 0 && !zr_marked_p(v)
end

# After marking: the live tables keep their place in the list, minus
# the entries whose weak side is unmarked.
sig [] => Void
machine def zr_weak_prune
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
machine def zr_weak_prune_table(h, finalizer)
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

# The queued rows are roots until they run.
sig [] => Void
machine def zr_mark_finalizer_queue
  q = zr_finalizer_queue()
  i = 0
  while i < WeakList.len(q)
    zr_mark(Machine.value(Machine.load64(WeakList.ptr(q) + (i * 8), 0)))
    i += 1
  end
end

# The finalizer table: object => [object_id, proc, ...], keys weak.
sig [] => Value
machine def zr_finalizers
  t = zr_global(G_FINALIZERS)
  if zr_special_p(t)
    t = zr_weak_table_new(WEAK_KEY, true)
    zr_set_global(G_FINALIZERS, t)
  end
  t
end

sig [] => Value
machine def zr_finalizers_m
  zr_finalizers()
end

# The queued finalizers, each proc called with its object's id; an
# error in one is printed and passed over. Runs after a collection the
# program asked for and at the next poll after any other, never inside
# an allocation.
sig [] => Value
machine def zr_finalizers_run
  q = zr_finalizer_queue()
  while WeakList.len(q) > 0
    n = WeakList.len(q) - 1
    row = Machine.value(Machine.load64(WeakList.ptr(q) + (n * 8), 0))
    WeakList.set_len(q, n)
    r = zr_finalizer_row_run(row)
    return r if r == QUNDEF
  end
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_finalizer_row_run(row)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(zr_ary_at(row, 0)))
  i = 1
  while i < RArray.len(row)
    r = zr_send(zr_ary_at(row, i), Machine.id(:call), 1, slot)
    if r == QUNDEF
      raised = Task.pending(zr_task())
      Task.set_pending(zr_task(), Machine.value(QNIL))
      zr_error_print(raised)
    end
    i += 1
  end
  Machine.value(QNIL)
end

# At the program's end every finalizer still registered runs, in
# registration order.
sig [] => Void
machine def zr_finalizers_at_exit
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
