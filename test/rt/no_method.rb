# A miss in dispatch: CRuby's message on stderr and exit status 1.
sig [] => Value
machine def zr_toplevel
  rec = Machine.slot(Frame.size + 8)
  meta = Machine.static(:meta, FrameMeta.size)
  FrameMeta.set_file(meta, Machine.bytes("no_method.rb"))
  FrameMeta.set_file_len(meta, 12)
  FrameMeta.set_kind(meta, KIND_MAIN)
  Frame.set_meta(rec, meta)
  Frame.set_line(rec, 9)
  Frame.set_prev(rec, Task.top(zr_task()))
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_lastline(rec, Machine.value(QNIL))
  Frame.set_serial(rec, 0)
  Frame.set_mid(rec, 0)
  # The collector marks `defined` with the rest of the record, so it
  # holds a Value like every other field it reads, not what the stack had.
  Frame.set_defined(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 1)
  Task.set_top(zr_task(), rec)
  argv = rec + Frame.size
  Machine.store64(argv, 0, Machine.word(zr_fix(7)))
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 1, argv)
  r = zr_no_method(zr_fix(7), Machine.id(:frobnicate), true, 0, argv)
  Task.set_top(zr_task(), Frame.prev(rec))
  r
end
