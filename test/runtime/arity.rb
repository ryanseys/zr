# The wrong number of arguments: CRuby's message and exit status 1.
module Zr::Kern
  sig [] => Value
  def zr_toplevel
    rec = Machine.slot(Frame.size + 8)
    meta = Machine.static(:meta, FrameMeta.size)
    FrameMeta.set_file(meta, Machine.bytes("arity.rb"))
    FrameMeta.set_file_len(meta, 8)
    FrameMeta.set_kind(meta, KIND_MAIN)
    Frame.set_meta(rec, meta)
    Frame.set_line(rec, 9)
    Frame.set_prev(rec, Task.top(zr_task()))
    Frame.set_self(rec, zr_global(G_MAIN))
    Frame.set_cref(rec, Machine.value(QNIL))
    Frame.set_blk(rec, Machine.value(QNIL))
    Frame.set_svars(rec, Machine.value(QNIL))
    Frame.set_serial(rec, 0)
    Frame.set_entry(rec, 0)
    # The collector marks `defined` with the rest of the record, so it
    # holds a Value like every other field it reads, not what the stack had.
    Frame.set_defined(rec, Machine.value(QNIL))
    Frame.set_nvalues(rec, 1)
    Task.set_top(zr_task(), rec)
    argv = rec + Frame.size
    Machine.store64(argv, 0, Machine.word(zr_fix(7)))
    r = zr_send(zr_fix(7), Machine.id(:succ), 1, argv)
    Task.set_top(zr_task(), Frame.prev(rec))
    r
  end
end
