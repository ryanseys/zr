module Zr::Kern
  # The C API's Regexps and MatchData, each through their Ruby methods.

  # rb_reg_new and rb_reg_new_str: `Regexp.new(source, options)`, of the
  # `len` bytes at `source` or of a String.
  #: (ptr, word, i32) -> value
  def rb_reg_new(source, len, options)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_reg_new(zr_str_new(source, len), options)
  end

  #: (value, i32) -> value
  def rb_reg_new_str(source, options)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_reg_new(source, options)
  end

  #: (value, i32) -> value
  def zr_capi_reg_new(source, options)
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(source))
    Machine.store64(args, 8, Machine.word(zr_fix(Machine.sword(options))))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Regexp)), Machine.id(:new), 2, args))
  end

  # rb_reg_match: `re =~ str`.
  #: (value, value) -> value
  def rb_reg_match(re, str)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(re, Machine.id(:=~), str)
  end

  # rb_reg_nth_match: group `nth` of the MatchData `match` (nil for none,
  # or for nil).
  #: (i32, value) -> value
  def rb_reg_nth_match(nth, match)
    Machine.gates_enter
    zr_c_entered()
    if match == QNIL
      return match
    end
    zr_capi_call1(match, Machine.id(:[]), zr_fix(Machine.sword(nth)))
  end

  # rb_reg_search: where `re` first matches `str` at or after `pos` (or,
  # `reverse`, at or before it), or -1.
  #: (value, value, word, i32) -> word
  def rb_reg_search(re, str, pos, reverse)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(re))
    Machine.store64(args, 8, Machine.word(zr_int_from_word(pos)))
    at = zr_c_result(zr_send(str, Machine.sword(reverse) != 0 ? Machine.id(:rindex) : Machine.id(:index), 2, args))
    at == QNIL ? 0 - 1 : zr_fix2long(at)
  end

  # rb_match_busy: keeps a MatchData from reuse; zr reuses none.
  #: (value) -> void
  def rb_match_busy(match)
    Machine.gates_enter
    zr_c_entered()
  end

  # rb_match_ensure_onig: RMATCH_REGS calls it, then reads the registers
  # in ruby's struct RMatch in the MatchData's cell. A MatchData of zr
  # keeps its offsets in Ruby, so the macro cannot work: C gets
  # NotImplementedError before it reads the cell.
  #: (value) -> void
  def rb_match_ensure_onig(match)
    Machine.gates_enter
    zr_c_entered()
    zr_c_raise(zr_core_class(Machine.id(:NotImplementedError)), Machine.bytes("zr has no RMATCH_REGS: a MatchData keeps its registers outside its cell"), 71)
  end

  # rb_lastline_get and rb_lastline_set: `$_` of the Ruby code that called
  # the C method; rb_backref_get and rb_backref_set: its `$~`.
  #: () -> value
  def rb_lastline_get
    Machine.gates_enter
    zr_c_entered()
    zr_lastline_get()
  end

  #: (value) -> void
  def rb_lastline_set(v)
    Machine.gates_enter
    zr_c_entered()
    zr_lastline_set(v)
  end

  #: () -> value
  def rb_backref_get
    Machine.gates_enter
    zr_c_entered()
    zr_backref_get()
  end

  #: (value) -> void
  def rb_backref_set(v)
    Machine.gates_enter
    zr_c_entered()
    zr_backref_set(v)
  end
end
