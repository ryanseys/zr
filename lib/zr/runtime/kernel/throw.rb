# `catch` and `throw`. A throw is a pending unwind to the catch whose tag
# is the same object. It runs each ensure on the way and skips each
# rescue. The task keeps the tags of the active catches, innermost last.

module Zr::Kern
  #: () -> value
  def zr_catches
    t = zr_task()
    list = Task[t].catches
    if list == QNIL
      list = zr_ary_new(8)
      # The runtime's own list, which ObjectSpace does not give out.
      RBasic[list].flags = RBasic[list].flags | FL_CONCEALED
      Task[t].catches = list
    end
    list
  end

  # Whether a catch for `tag` is active.
  #: (value) -> value
  def zr_catch_tag_p(tag)
    list = zr_catches()
    i = RArray[list].len - 1
    while i >= 0
      if zr_ary_at(list, i) == tag
        return Machine.value(QTRUE)
      end
      i -= 1
    end
    Machine.value(QFALSE)
  end

  # Starts the pending unwind for a throw. The caller has already checked
  # that a catch for `tag` is active.
  #: (value, value) -> value
  def zr_throw(tag, value)
    Task[zr_task()].throw_tag = tag
    zr_signal(PENDING_THROW, value, 0, 0)
  end

  # Runs the block with a catch for `tag`. A throw to `tag` gives the
  # return value.
  #: (value, value) -> value
  def zr_catch(tag, blk)
    list = zr_catches()
    zr_ary_push(list, tag)
    slot = Machine.slot(8)
    Machine.store64(slot, 0, Machine.word(tag))
    r = zr_yield(blk, 1, slot)
    RArray[list].len = RArray[list].len - 1
    t = zr_task()
    if r == QUNDEF && Task[t].pending_kind == PENDING_THROW && Task[t].throw_tag == tag
      r = Task[t].pending
      Task[t].pending_kind = PENDING_RAISE
      Task[t].pending = Machine.value(QNIL)
      Task[t].throw_tag = Machine.value(QNIL)
    end
    r
  end
end
