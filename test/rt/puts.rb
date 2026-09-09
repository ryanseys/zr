# The kernel through a hand-written toplevel: puts of a fixnum, a
# string, a symbol, a negative number, and nothing, every argument
# rooted in one frame record; then a thousand strings under the
# collector.
sig [] => Value
machine def zr_toplevel
  rec = Machine.slot(Frame.size + 32)
  meta = Machine.static(:meta, FrameMeta.size)
  FrameMeta.set_kind(meta, KIND_MAIN)
  Frame.set_meta(rec, meta)
  Frame.set_prev(rec, Task.top(zr_task()))
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_cref(rec, Machine.value(QNIL))
  Frame.set_blk(rec, Machine.value(QNIL))
  Frame.set_svar(rec, Machine.value(QNIL))
  Frame.set_nvalues(rec, 4)
  Task.set_top(zr_task(), rec)
  argv = rec + Frame.size
  Machine.store64(argv, 0, Machine.word(zr_fix(1)))
  Machine.store64(argv, 8, Machine.word(QNIL))
  Machine.store64(argv, 16, Machine.word(QNIL))
  Machine.store64(argv, 24, Machine.word(QNIL))
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 1, argv)
  Machine.store64(argv, 8, Machine.word(zr_str_new(Machine.bytes("two\n"), 4)))
  Machine.store64(argv, 16, Machine.word(zr_sym(Machine.id(:three))))
  Machine.store64(argv, 24, Machine.word(zr_fix(0 - 4)))
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 4, argv)
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 0, argv)
  n = 0
  while n < 1000
    Machine.store64(argv, 0, Machine.word(zr_str_new(Machine.bytes("x"), 1)))
    n += 1
  end
  zr_send(zr_global(G_MAIN), Machine.id(:puts), 1, argv)
  Task.set_top(zr_task(), Frame.prev(rec))
  Machine.value(QNIL)
end
