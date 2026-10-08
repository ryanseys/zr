module Zr::Kern
  # The private functions of CRuby's instruction sequences that debuggers
  # and coverage tools declare for themselves (debug, datadog-ci). An
  # rb_iseq_t * is the address of the FrameMeta of the code, and its
  # wrapper is the RubyVM::InstructionSequence of that code, which keeps
  # the address (`__meta__`). The answers come from Ruby
  # (RubyVM.iseq_answer).

  # rb_iseqw_new: the RubyVM::InstructionSequence of the code `iseq`.
  #: (ptr) -> value
  def rb_iseqw_new(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:wrapper), Machine.value(QFALSE))
  end

  # rb_iseqw_to_iseq: the code of a RubyVM::InstructionSequence; NULL for
  # one that has no FrameMeta (a string that it compiled and kept).
  #: (value) -> ptr
  def rb_iseqw_to_iseq(iseqw)
    Machine.gates_enter
    zr_c_entered()
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(iseqw))
    meta = zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:RubyVM)), Machine.id(:iseq_meta), 1, argv))
    zr_fixnum_p(meta) ? Machine.ptr(zr_fix2long(meta)) : Machine.ptr(0)
  end

  # rb_iseq_code_location: where the code starts and ends. zr keeps the
  # lines of each scope and no columns, so both columns are 0.
  #: (ptr, ptr, ptr, ptr, ptr) -> void
  def rb_iseq_code_location(iseq, first_line, first_column, last_line, last_column)
    Machine.gates_enter
    zr_c_entered()
    first = iseq == 0 ? 0 : FrameMeta[iseq].line
    last = iseq == 0 ? 0 : FrameMeta[iseq].end_line
    zr_capi_store_int(first_line, first)
    zr_capi_store_int(first_column, 0)
    zr_capi_store_int(last_line, last == 0 ? first : last)
    zr_capi_store_int(last_column, 0)
  end

  #: (ptr) -> value
  def rb_iseq_path(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:path), Machine.value(QFALSE))
  end

  #: (ptr) -> value
  def rb_iseq_realpath(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:realpath), Machine.value(QFALSE))
  end

  #: (ptr) -> value
  def rb_iseq_label(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:label), Machine.value(QFALSE))
  end

  #: (ptr) -> value
  def rb_iseq_first_lineno(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:first_lineno), Machine.value(QFALSE))
  end

  # rb_iseq_type: the kind of the code, as RubyVM::InstructionSequence's
  # `type` names it (:method, :block, :class, :top, :main, :eval).
  #: (ptr) -> value
  def rb_iseq_type(iseq)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:type), Machine.value(QFALSE))
  end

  # rb_iseq_parameters: the parameters of the code, as a method takes
  # them, or as a proc does when `is_proc`.
  #: (ptr, i32) -> value
  def rb_iseq_parameters(iseq, is_proc)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_iseq(iseq, Machine.id(:parameters), zr_bool(Machine.sword(is_proc) != 0))
  end

  # The answer `what` about the code `iseq` (RubyVM.iseq_answer); nil for
  # no code.
  #: (ptr, word, value) -> value
  def zr_capi_iseq(iseq, what, is_proc)
    if iseq == 0
      return Machine.value(QNIL)
    end
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(zr_fix(Machine.word(iseq))))
    Machine.store64(argv, 8, Machine.word(zr_sym(what)))
    Machine.store64(argv, 16, Machine.word(is_proc))
    zr_c_result(zr_trace_point_send(zr_core_class(Machine.id(:RubyVM)), Machine.id(:iseq_answer), 3, argv))
  end

  # Stores the C int `n` at `at`, when C gave a place for it.
  #: (ptr, word) -> void
  def zr_capi_store_int(at, n)
    if at != 0
      Machine.store32(at, 0, Machine.i32(n))
    end
  end
end
