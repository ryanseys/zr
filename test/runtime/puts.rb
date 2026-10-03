# The kernel through a hand-written toplevel: puts of a fixnum, a
# string, a symbol, a negative number, and nothing, every argument
# rooted in one frame record; then a thousand strings under the
# collector.
module Zr::Kern
  #: () -> value
  def zr_toplevel
    rec = Machine.slot(Frame.size + 32)
    meta = Machine.static(:meta, FrameMeta.size)
    FrameMeta[meta].kind = KIND_MAIN
    Frame[rec].meta = meta
    Frame[rec].prev = Task[zr_task()].top
    Frame[rec].self = zr_global(G_MAIN)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].line = 0
    Frame[rec].serial = 0
    Frame[rec].entry = 0
    # The collector marks `defined` with the rest of the record, so it
    # holds a Value like every other field it reads, not what the stack had.
    Frame[rec].defined = Machine.value(QNIL)
    Frame[rec].nvalues = 4
    Task[zr_task()].top = rec
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
    Task[zr_task()].top = Frame[rec].prev
    Machine.value(QNIL)
  end
end
