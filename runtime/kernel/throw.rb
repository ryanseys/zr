# `catch` and `throw`: a throw is a signal that unwinds to the catch
# whose tag is the same object, running every ensure on the way and
# passing every rescue. The task keeps the tags of the catches in
# flight, innermost last.

sig [] => Value
machine def zr_catches
  t = zr_task()
  list = Task.catches(t)
  if list == QNIL
    list = zr_ary_new(8)
    Task.set_catches(t, list)
  end
  list
end

# Whether a catch for `tag` is in flight.
sig [Value] => Value
machine def zr_catch_tag_p(tag)
  list = zr_catches()
  i = RArray.len(list) - 1
  while i >= 0
    if zr_ary_at(list, i) == tag
      return Machine.value(QTRUE)
    end
    i -= 1
  end
  Machine.value(QFALSE)
end

# The throw signal; the caller has checked a catch waits for it.
sig [Value, Value] => Value
machine def zr_throw(tag, value)
  Task.set_throw_tag(zr_task(), tag)
  zr_signal(PENDING_THROW, value, 0, 0)
end

# The block run with `tag` catchable; a throw to it is the answer.
sig [Value, Value] => Value
machine def zr_catch(tag, blk)
  list = zr_catches()
  zr_ary_push(list, tag)
  slot = Machine.slot(8)
  Machine.store64(slot, 0, Machine.word(tag))
  r = zr_yield(blk, 1, slot)
  RArray.set_len(list, RArray.len(list) - 1)
  t = zr_task()
  if r == QUNDEF && Task.pending_kind(t) == PENDING_THROW && Task.throw_tag(t) == tag
    r = Task.pending(t)
    Task.set_pending_kind(t, PENDING_RAISE)
    Task.set_pending(t, Machine.value(QNIL))
    Task.set_throw_tag(t, Machine.value(QNIL))
  end
  r
end
