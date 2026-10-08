module Zr::Kern
  # Calls into C, and the way back out of C when an unwind must skip C's
  # frames.
  #
  # zr unwinds by return: a function that raises returns undef, and each
  # caller passes it on. C code does not: CRuby's rb_raise longjmps over
  # the C frames to the innermost rb_protect, or to where ruby called the C
  # method. A C frame record (`CFrame`) is that target here. zr_call_c
  # links one into the task before it calls C, and zr_cframe_call saves a
  # machine context in it. When a C-API function that C called gets undef
  # from zr code, it calls zr_c_unwind: that drops the C frames, and the
  # zr_call_c that made the record returns undef, so the unwind goes on as
  # a return.
  #
  # The record also bounds the C frames for the collector. C keeps Values
  # in its frames and registers, where no frame record of zr's lists them.
  # `lo` and `hi` bound the stack that C's frames use: `hi` is the record,
  # in the frame of zr_call_c's caller, and each C-API function sets `lo`
  # to a slot of its own frame when C calls it. A function that foreign
  # code enters saves every callee-saved register in its frame, so C's
  # registers are in that range too.
  class CFrame < Layout
    attr_accessor :prev #: ptr
    attr_accessor :lo #: ptr
    attr_accessor :hi #: ptr
    # The task's frame list and the kernel root chain as they were before
    # C ran: a leap restores them.
    attr_accessor :top #: ptr
    attr_accessor :kroots #: ptr
  end

  # zr_cframe_call saves its context after the record's fields.
  CFRAME_BYTES = 40 + CONTEXT_BYTES

  # C code can run the collector: it calls back into zr.
  collects :zr_call_c

  # Calls the C function `fn` with the `argc` words at `argv`, which holds
  # at least eight words, and returns its result. It returns undef when a
  # C-API function unwound out of C (zr_c_unwind); the unwind is then the
  # task's pending one.
  #: (ptr, ptr, word) -> word
  def zr_call_c(fn, argv, argc)
    rec = Machine.slot(CFRAME_BYTES)
    zr_cframe_push(rec)
    r = zr_cframe_call(rec, fn, argv, argc)
    zr_cframe_pop(rec)
    # A callback can set a gate while C runs, and C gives back the x28 it
    # got, so the gate word comes from its static again.
    Machine.gates_set(Machine.load64(Machine.static(:gates, 8), 0))
    r
  end

  # Calls `fn` as zr_call_c does, for its effect: whether it returned,
  # false when a C-API function unwound out of it. A C function may give
  # undef itself (json's ensure function does), which zr_call_c's answer
  # cannot tell from an unwind; zr_c_unwind marks the record instead.
  #: (ptr, ptr, word) -> bool
  def zr_call_c_returned(fn, argv, argc)
    rec = Machine.slot(CFRAME_BYTES)
    zr_cframe_push(rec)
    zr_cframe_call(rec, fn, argv, argc)
    zr_cframe_pop(rec)
    Machine.gates_set(Machine.load64(Machine.static(:gates, 8), 0))
    CFrame[rec].hi != 0
  end

  # Calls `fn(data)` for the collector: a T_DATA's mark, free or size
  # function (data_object.rb). The collector stops an allocation in it
  # (zr_alloc_slow), so this call, unlike zr_call_c, cannot collect, and
  # the collector's own frames keep no roots for it. No Ruby code runs in
  # it, so no gate changes.
  #: (ptr, ptr) -> word
  def zr_call_c_in_gc(fn, data)
    # The record bounds the C frames for a C-API function that this C
    # calls (zr_c_entered); a leap from here stops (zr_c_unwind), so the
    # call saves no context in it.
    rec = Machine.slot(CFRAME_BYTES)
    zr_cframe_push(rec)
    r = zr_gc_call(fn, data)
    zr_cframe_pop(rec)
    r
  end

  # Links the C frame record `rec` into the task as its innermost.
  #: (ptr) -> void
  def zr_cframe_push(rec)
    t = zr_task()
    CFrame[rec].prev = Task[t].cframe
    # Nothing to scan until a C-API function marks the low end.
    CFrame[rec].lo = rec
    CFrame[rec].hi = rec
    CFrame[rec].top = Task[t].top
    CFrame[rec].kroots = Machine.ptr(Machine.load64(zr_kroots(), 0))
    Task[t].cframe = rec
  end

  # Unlinks `rec` after its C call returned.
  #: (ptr) -> void
  def zr_cframe_pop(rec)
    Task[zr_task()].cframe = CFrame[rec].prev
  end

  # The C frames of the innermost C call end at `low`, a slot below the
  # frame of the C-API function that C called (`zr_c_entered`).
  #: (ptr) -> void
  def zr_c_frames_end(low)
    rec = Task[zr_task()].cframe
    if rec != 0
      CFrame[rec].lo = low
    end
  end

  # Unwinds out of the innermost C call: its zr_call_c returns undef. A
  # C-API function calls this after the zr code that it called returned
  # undef, so the task's pending unwind is set, and no zr frame is
  # skipped: each one returned already. Only C's frames and the C-API
  # function's own are dropped, as CRuby's longjmp drops them.
  #: () -> void
  def zr_c_unwind
    t = zr_task()
    rec = Task[t].cframe
    if rec == 0
      zr_bug(Machine.bytes("[BUG] an unwind out of C, with no C call to unwind to\n"), 54)
    end
    # A mark or free function runs in a collection, which an unwind would
    # leave half done.
    if Heap[zr_heap()].collecting != 0
      zr_bug(Machine.bytes("[BUG] an unwind out of C while the collector runs\n"), 50)
    end
    Task[t].top = CFrame[rec].top
    Machine.store64(zr_kroots(), 0, Machine.word(CFrame[rec].kroots))
    Task[t].cframe = CFrame[rec].prev
    # The record bounds no C frames now; its call left (zr_call_c_returned).
    CFrame[rec].hi = 0
    zr_cframe_leap(rec)
  end
end
