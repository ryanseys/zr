# The wrong number of arguments: CRuby's message and exit status 1.
module Zr::Kern
  #: () -> value
  def zr_toplevel
    rec = Machine.slot(Frame.size + 8)
    meta = Machine.static(:meta, FrameMeta.size)
    FrameMeta[meta].file = Machine.bytes("arity.rb")
    FrameMeta[meta].file_len = 8
    FrameMeta[meta].kind = KIND_MAIN
    Frame[rec].meta = meta
    Frame[rec].line = 9
    Frame[rec].prev = Task[zr_task()].top
    Frame[rec].self = zr_global(G_MAIN)
    Frame[rec].cref = Machine.value(QNIL)
    Frame[rec].blk = Machine.value(QNIL)
    Frame[rec].svars = Machine.value(QNIL)
    Frame[rec].serial = 0
    Frame[rec].entry = 0
    # The collector marks `defined` with the rest of the record, so it
    # holds a Value like every other field it reads, not what the stack had.
    Frame[rec].defined = Machine.value(QNIL)
    Frame[rec].nvalues = 1
    Task[zr_task()].top = rec
    argv = rec + Frame.size
    Machine.store64(argv, 0, Machine.word(zr_fix(7)))
    r = zr_send(zr_fix(7), Machine.id(:succ), 1, argv)
    Task[zr_task()].top = Frame[rec].prev
    r
  end
end
