# Regexp over oniguruma: a T_REGEXP cell holds the compiled pattern;
# a search answers the byte offsets of every group. The last match
# (`$~`) lives in the frame record of the method that asked, as
# CRuby keeps it.
Machine.import "onig_initialize", [Ptr, I32] => I32
Machine.import "onig_new", [Ptr, Ptr, Ptr, I32, Ptr, Ptr, Ptr] => I32
Machine.import "onig_free", [Ptr] => Void
Machine.import "onig_search", [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, I32] => I32
Machine.import "onig_match", [Ptr, Ptr, Ptr, Ptr, Ptr, I32] => I32
Machine.import "onig_region_new", [] => Ptr
Machine.import "onig_region_free", [Ptr, I32] => Void
Machine.import "onig_number_of_captures", [Ptr] => I32
Machine.import "onig_foreach_name", [Ptr, Ptr, Ptr] => I32

Machine.struct :RRegexp, basic: RBasic, source: Value, options: Word, reg: Ptr, names: Value
T_REGEXP = 31
# ONIG_OPTION_WORD_IS_ASCII | DIGIT_IS_ASCII | SPACE_IS_ASCII: Ruby's \w, \d, \s and \b stay ASCII.
ASCII_CLASSES = 458752
G_REGEXP = 42
G_REGEXP_LITERALS = 43

sig [] => Void
machine def zr_onig_ready
  flag = Machine.static(:onig_ready, 8)
  if Machine.load64(flag, 0) == 0
    encodings = Machine.slot(16)
    Machine.store64(encodings, 0, Machine.word(Machine.extern(:OnigEncodingUTF8)))
    Machine.store64(encodings, 8, Machine.word(Machine.extern(:OnigEncodingASCII)))
    onig_initialize(encodings, Machine.i32(2))
    Machine.store64(flag, 0, 1)
  end
end

# The pattern `source` compiled with `options` (Ruby's bits, which
# are oniguruma's): the Regexp, or [error code, the text the error
# points at] for the core to raise.
sig [Value, Value, Value] => Value
machine def zr_regexp_compile(klass, source, options)
  zr_onig_ready()
  reg = Machine.slot(8)
  info = Machine.slot(24)
  Machine.store64(info, 0, 0)
  Machine.store64(info, 8, 0)
  Machine.store64(info, 16, 0)
  enc = zr_str_binary_p(source) ? Machine.extern(:OnigEncodingASCII) : Machine.extern(:OnigEncodingUTF8)
  r = onig_new(reg, RString.ptr(source), RString.ptr(source) + RString.len(source), Machine.i32((zr_fix2long(options) & 7) | ASCII_CLASSES), enc, Machine.extern(:OnigSyntaxRuby), info)
  if r != Machine.i32(0)
    out = zr_ary_new(2)
    code = Machine.word(r)
    if code >= 2147483648
      code -= 4294967296
    end
    zr_ary_push(out, zr_fix(code))
    par = Machine.ptr(Machine.load64(info, 8))
    par_end = Machine.ptr(Machine.load64(info, 16))
    zr_ary_push(out, par == 0 ? Machine.value(QNIL) : zr_str_new(par, par_end - par))
    return out
  end
  re = zr_alloc(T_REGEXP, klass)
  RRegexp.set_source(re, source)
  RRegexp.set_options(re, zr_fix2long(options))
  RRegexp.set_reg(re, Machine.ptr(Machine.load64(reg, 0)))
  RRegexp.set_names(re, Machine.value(QNIL))
  re
end

# A regexp literal: compiled the first time its site runs, then the
# same frozen object, held in the literal table by the site's index.
sig [Word, Ptr, Word, Word] => Value
machine def zr_regexp_literal(index, bytes, len, options)
  table = zr_global(G_REGEXP_LITERALS)
  if zr_special_p(table)
    table = zr_ary_new(8)
    zr_set_global(G_REGEXP_LITERALS, table)
  end
  while RArray.len(table) <= index
    zr_ary_push(table, Machine.value(QNIL))
  end
  re = zr_ary_at(table, index)
  if re != QNIL
    return re
  end
  source = zr_str_frozen(bytes, len)
  re = zr_regexp_compile(zr_global(G_REGEXP), source, zr_fix(options))
  if zr_type(re) == T_ARRAY
    return zr_raise_msg(zr_core_class(Machine.id(:RegexpError)), Machine.bytes("regexp literal"), 14)
  end
  RBasic.set_flags(re, RBasic.flags(re) | FL_FREEZE)
  zr_ary_store(table, index, re)
  re
end

sig [Value] => Value
machine def zr_regexp_source(re)
  RRegexp.source(re)
end

sig [Value] => Value
machine def zr_regexp_options(re)
  zr_fix(RRegexp.options(re))
end

sig [Value] => Value
machine def zr_regexp_p(v)
  zr_bool(!zr_special_p(v) && zr_type(v) == T_REGEXP)
end

sig [Value] => Value
machine def zr_regexp_captures(re)
  zr_fix(Machine.word(onig_number_of_captures(RRegexp.reg(re))))
end

# The named groups: [[name, [group numbers]], ...].
sig [Value] => Value
machine def zr_regexp_names(re)
  if RRegexp.names(re) != QNIL
    return RRegexp.names(re)
  end
  out = zr_ary_new(4)
  onig_foreach_name(RRegexp.reg(re), Machine.addr(:zr_regexp_name_row), Machine.ptr(Machine.word(out)))
  RRegexp.set_names(re, out)
  out
end

sig [Ptr, Ptr, I32, Ptr, Ptr, Ptr] => I32
machine def zr_regexp_name_row(name, name_end, count, groups, reg, arg)
  out = Machine.value(Machine.word(arg))
  row = zr_ary_new(2)
  zr_ary_push(row, zr_str_new(name, name_end - name))
  numbers = zr_ary_new(2)
  i = 0
  while i < Machine.word(count)
    n = Machine.word(Machine.load32(groups + (i * 4), 0))
    zr_ary_push(numbers, zr_fix(n))
    i += 1
  end
  zr_ary_push(row, numbers)
  zr_ary_push(out, row)
  Machine.i32(0)
end

# Search `str` from byte `start` (backwards to it when `backward`):
# nil, or the byte offsets [begin0, end0, begin1, end1, ...], -1 for
# a group that did not take part.
sig [Value, Value, Value, Value] => Value
machine def zr_regexp_search(re, str, start, backward)
  region = onig_region_new()
  base = RString.ptr(str)
  stop = base + RString.len(str)
  from = base + zr_fix2long(start)
  range = backward == QTRUE ? base : stop
  r = onig_search(RRegexp.reg(re), base, stop, from, range, region, Machine.i32(0))
  code = Machine.word(r)
  if code >= 2147483648
    onig_region_free(region, Machine.i32(1))
    return Machine.value(QNIL)
  end
  out = zr_region_offsets(region)
  onig_region_free(region, Machine.i32(1))
  out
end

# Match `str` at exactly byte `start`, as `\A`-anchored would.
sig [Value, Value, Value] => Value
machine def zr_regexp_match_at(re, str, start)
  region = onig_region_new()
  base = RString.ptr(str)
  stop = base + RString.len(str)
  r = onig_match(RRegexp.reg(re), base, stop, base + zr_fix2long(start), region, Machine.i32(0))
  code = Machine.word(r)
  if code >= 2147483648
    onig_region_free(region, Machine.i32(1))
    return Machine.value(QNIL)
  end
  out = zr_region_offsets(region)
  onig_region_free(region, Machine.i32(1))
  out
end

sig [Ptr] => Value
machine def zr_region_offsets(region)
  n = Machine.word(Machine.load32(region, 4))
  begs = Machine.ptr(Machine.load64(region, 8))
  ends = Machine.ptr(Machine.load64(region, 16))
  out = zr_ary_new(n * 2)
  i = 0
  while i < n
    b = Machine.word(Machine.load32(begs + (i * 4), 0))
    e = Machine.word(Machine.load32(ends + (i * 4), 0))
    if b >= 2147483648
      b = 0 - 1
    end
    if e >= 2147483648
      e = 0 - 1
    end
    zr_ary_push(out, zr_fix(b))
    zr_ary_push(out, zr_fix(e))
    i += 1
  end
  out
end

sig [Value] => Void
machine def zr_mark_regexp(re)
  zr_mark(RRegexp.source(re))
  zr_mark(RRegexp.names(re))
end

sig [Value] => Void
machine def zr_release_regexp(re)
  if RRegexp.reg(re) != 0
    onig_free(RRegexp.reg(re))
  end
end

# The frame record whose `$~` the running code sees: a block's is its
# method's; a core method's is its caller's.
sig [] => Ptr
machine def zr_backref_home
  rec = Task.top(zr_task())
  while rec != 0
    meta = Frame.meta(rec)
    if meta == 0
      return rec
    end
    if FrameMeta.file_len(meta) == 0
      rec = Frame.prev(rec)
    elsif (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN) && FrameMeta.parent(meta) != 0
      parent = FrameMeta.parent(meta)
      up = Frame.prev(rec)
      while up != 0 && Frame.meta(up) != parent
        up = Frame.prev(up)
      end
      if up == 0
        return rec
      end
      rec = up
    else
      return rec
    end
  end
  0
end

sig [Value] => Value
machine def zr_backref_set(v)
  home = zr_backref_home()
  if home != 0
    Frame.set_svar(home, v)
  end
  v
end

sig [] => Value
machine def zr_backref_get
  home = zr_backref_home()
  home == 0 ? Machine.value(QNIL) : Frame.svar(home)
end
