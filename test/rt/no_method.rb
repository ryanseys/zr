# A miss in dispatch: CRuby's message on stderr and exit status 1.
sig [] => Value
machine def zr_toplevel
  rec = Machine.slot(Frame.size + 8)
  meta = Machine.static(:meta, 64)
  FrameMeta.set_file(meta, Machine.bytes("no_method.rb"))
  FrameMeta.set_file_len(meta, 12)
  FrameMeta.set_kind(meta, KIND_MAIN)
  Frame.set_meta(rec, meta)
  Frame.set_line(rec, 9)
  Frame.set_prev(rec, Task.top(zr_task()))
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 1)
  Task.set_top(zr_task(), rec)
  argv = rec + Frame.size
  Machine.store64(argv, 0, Machine.word(zr_fix(7)))
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 1, argv)
  r = zr_vcall(zr_fix(7), Machine.id(:frobnicate), 0, argv)
  return r if r == QUNDEF
  Machine.value(QNIL)
end
