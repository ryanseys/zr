# The wrong number of arguments: CRuby's message and exit status 1.
sig [] => Value
machine def zr_toplevel
  rec = Machine.slot(Frame.size + 8)
  Frame.set_prev(rec, Task.top(zr_task()))
  Frame.set_self(rec, zr_global(G_MAIN))
  Frame.set_nvalues(rec, 1)
  Task.set_top(zr_task(), rec)
  argv = rec + Frame.size
  Machine.store64(argv, 0, Machine.word(zr_fix(7)))
  zr_send(zr_fix(7), Machine.id(:to_s), 1, argv)
  Machine.value(QNIL)
end
