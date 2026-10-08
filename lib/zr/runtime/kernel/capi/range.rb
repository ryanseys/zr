module Zr::Kern
  # The C API's Ranges and arithmetic sequences.

  # rb_range_new: `Range.new(beg, en, exclude_end)`.
  #: (value, value, i32) -> value
  def rb_range_new(beg, en, exclude_end)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(24)
    Machine.store64(args, 0, Machine.word(beg))
    Machine.store64(args, 8, Machine.word(en))
    Machine.store64(args, 16, Machine.word(zr_bool(Machine.sword(exclude_end) != 0)))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Range)), Machine.id(:new), 3, args))
  end

  # rb_range_values: the begin, the end and whether the end is excluded
  # of a Range, or of an object that answers `begin`, `end` and
  # `exclude_end?`, into `*begp`, `*endp` and `*exclp`. Returns ruby's
  # Qtrue as an int (20) when it has them, else 0; an arithmetic sequence
  # has none.
  #: (value, ptr, ptr, ptr) -> i32
  def rb_range_values(range, begp, endp, exclp)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_range_values(range, begp, endp, exclp) ? Machine.i32(QTRUE) : Machine.i32(0)
  end

  #: (value, ptr, ptr, ptr) -> bool
  def zr_capi_range_values(range, begp, endp, exclp)
    if !zr_is_a(range, zr_core_class(Machine.id(:Range)))
      if zr_is_a(range, zr_capi_arith_seq_class())
        return false
      end
      if zr_c_result(zr_check_funcall(range, Machine.id(:begin))) != QTRUE ||
         zr_c_result(zr_check_funcall(range, Machine.id(:end))) != QTRUE ||
         zr_c_result(zr_check_funcall(range, Machine.id(:exclude_end?))) != QTRUE
        return false
      end
    end
    Machine.store64(begp, 0, Machine.word(zr_c_result(zr_send(range, Machine.id(:begin), 0, Machine.ptr(0)))))
    Machine.store64(endp, 0, Machine.word(zr_c_result(zr_send(range, Machine.id(:end), 0, Machine.ptr(0)))))
    excl = zr_c_result(zr_send(range, Machine.id(:exclude_end?), 0, Machine.ptr(0)))
    Machine.store32(exclp, 0, Machine.i32(excl != QNIL && excl != QFALSE ? 1 : 0))
    true
  end

  # rb_arithmetic_sequence_components_t: the begin, the end and the step,
  # then whether the end is excluded (an int).
  class ArithSeqComponents < Layout
    attr_accessor :begin #: value
    attr_accessor :end #: value
    attr_accessor :step #: value
    attr_accessor :exclude_end #: word
  end

  # rb_arithmetic_sequence_extract: the components of an arithmetic
  # sequence (`1.step(10, 3)`, `(1..10) % 3`), or of a Range with a step
  # of 1, into `*out`. 1 when `obj` is one, else 0.
  #: (value, ptr) -> i32
  def rb_arithmetic_sequence_extract(obj, out)
    Machine.gates_enter
    zr_c_entered()
    if zr_is_a(obj, zr_capi_arith_seq_class())
      ArithSeqComponents[out].begin = zr_c_result(zr_send(obj, Machine.id(:begin), 0, Machine.ptr(0)))
      ArithSeqComponents[out].end = zr_c_result(zr_send(obj, Machine.id(:end), 0, Machine.ptr(0)))
      ArithSeqComponents[out].step = zr_c_result(zr_send(obj, Machine.id(:step), 0, Machine.ptr(0)))
      excl = zr_c_result(zr_send(obj, Machine.id(:exclude_end?), 0, Machine.ptr(0)))
      Machine.store32(out + 24, 0, Machine.i32(excl == QTRUE ? 1 : 0))
      return Machine.i32(1)
    end
    if zr_capi_range_values(obj, out, out + 8, out + 24)
      ArithSeqComponents[out].step = zr_fix(1)
      return Machine.i32(1)
    end
    Machine.i32(0)
  end

  #: () -> value
  def zr_capi_arith_seq_class
    zr_capi_nested(Machine.id(:Enumerator), Machine.id(:ArithmeticSequence))
  end
end
