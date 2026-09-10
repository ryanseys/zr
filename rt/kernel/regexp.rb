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

# `reg` is the pattern the source's own encoding built; `alt` is the
# byte-oriented twin a byte-oriented subject asks for, compiled on
# first use from `text`, the engine text.
Machine.struct :RRegexp, basic: RBasic, source: Value, options: Word, reg: Ptr, names: Value, text: Value, alt: Ptr
T_REGEXP = 31
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

# The pattern `source` (what the engine reads), compiled with `options`
# (Ruby's bits, which are oniguruma's): the Regexp, or [error code, the
# text the error points at] for the core to raise. `shown` is the text
# as written, which the Regexp reports as its source.
sig [Value, Value, Value, Value] => Value
machine def zr_regexp_compile(klass, source, shown, options)
  zr_onig_ready()
  reg = Machine.slot(8)
  info = Machine.slot(24)
  Machine.store64(info, 0, 0)
  Machine.store64(info, 8, 0)
  Machine.store64(info, 16, 0)
  enc = zr_str_wide_p(source) ? Machine.extern(:OnigEncodingUTF8) : Machine.extern(:OnigEncodingASCII)
  r = onig_new(reg, RString.ptr(source), RString.ptr(source) + RString.len(source), Machine.i32(zr_fix2long(options) & 7), enc, Machine.extern(:OnigSyntaxRuby), info)
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
  RRegexp.set_text(re, source)
  RRegexp.set_alt(re, 0)
  RRegexp.set_source(re, shown)
  RRegexp.set_options(re, zr_fix2long(options))
  RRegexp.set_reg(re, Machine.ptr(Machine.load64(reg, 0)))
  RRegexp.set_names(re, Machine.value(QNIL))
  re
end

# A copy's own compiled pattern, from the engine text the core rebuilds
# for it; the text compiled once already, so it compiles again.
sig [Value, Value] => Value
machine def zr_regexp_recompile(re, text)
  reg = Machine.slot(8)
  info = Machine.slot(24)
  Machine.store64(info, 0, 0)
  Machine.store64(info, 8, 0)
  Machine.store64(info, 16, 0)
  enc = zr_str_wide_p(text) ? Machine.extern(:OnigEncodingUTF8) : Machine.extern(:OnigEncodingASCII)
  onig_new(reg, RString.ptr(text), RString.ptr(text) + RString.len(text), Machine.i32(RRegexp.options(re) & 7), enc, Machine.extern(:OnigSyntaxRuby), info)
  RRegexp.set_text(re, text)
  RRegexp.set_alt(re, 0)
  RRegexp.set_reg(re, Machine.ptr(Machine.load64(reg, 0)))
  re
end

# The pattern to search `str` with. A regexp built from ASCII source
# reads any ASCII-compatible subject, so a byte-oriented subject gets
# a byte-oriented pattern over the same engine text.
sig [Value, Value] => Ptr
machine def zr_regexp_reg_for(re, str)
  if zr_str_wide_p(str) == zr_str_wide_p(RRegexp.text(re))
    return RRegexp.reg(re)
  end
  if RRegexp.alt(re) == 0
    reg = Machine.slot(8)
    Machine.store64(reg, 0, 0)
    info = Machine.slot(24)
    Machine.store64(info, 0, 0)
    Machine.store64(info, 8, 0)
    Machine.store64(info, 16, 0)
    text = RRegexp.text(re)
    enc = zr_str_wide_p(str) ? Machine.extern(:OnigEncodingUTF8) : Machine.extern(:OnigEncodingASCII)
    r = onig_new(reg, RString.ptr(text), RString.ptr(text) + RString.len(text), Machine.i32(RRegexp.options(re) & 7), enc, Machine.extern(:OnigSyntaxRuby), info)
    # The text may hold bytes the other encoding refuses, and then the
    # pattern it already has is the only one there is.
    if r != Machine.i32(0)
      return RRegexp.reg(re)
    end
    RRegexp.set_alt(re, Machine.ptr(Machine.load64(reg, 0)))
  end
  RRegexp.alt(re)
end

# A regexp literal: compiled by the core the first time its site runs,
# then the same frozen object, held in the literal table by the site's
# index.
sig [Word, Ptr, Word, Word, Word] => Value
machine def zr_regexp_literal(index, bytes, len, options, pinned)
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
  slot = Machine.slot(24)
  Machine.store64(slot, 0, Machine.word(zr_str_frozen(bytes, len)))
  Machine.store64(slot, 8, Machine.word(zr_fix(options)))
  Machine.store64(slot, 16, Machine.word(pinned < 0 ? Machine.value(QNIL) : zr_fix(pinned)))
  re = zr_send(zr_global(G_REGEXP), Machine.id(:literal), 3, slot)
  return re if re == QUNDEF
  RBasic.set_flags(re, RBasic.flags(re) | FL_FREEZE)
  zr_ary_store(table, index, re)
  re
end

# `/#{x}/o`: the site's regexp, made once. nil until the site has run.
sig [Word] => Value
machine def zr_regexp_once(index)
  table = zr_global(G_REGEXP_LITERALS)
  if zr_special_p(table) || RArray.len(table) <= index
    return Machine.value(QNIL)
  end
  zr_ary_at(table, index)
end

sig [Word, Value] => Value
machine def zr_regexp_once_set(index, re)
  table = zr_global(G_REGEXP_LITERALS)
  if zr_special_p(table)
    table = zr_ary_new(8)
    zr_set_global(G_REGEXP_LITERALS, table)
  end
  while RArray.len(table) <= index
    zr_ary_push(table, Machine.value(QNIL))
  end
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
# nil, or [position, begin0, end0, begin1, end1, ...]: the byte the
# match started at (before a `\K`), then every group's offsets, -1
# for a group that did not take part.
sig [Value, Value, Value, Value] => Value
machine def zr_regexp_search(re, str, start, backward)
  region = onig_region_new()
  base = RString.ptr(str)
  stop = base + RString.len(str)
  from = base + zr_fix2long(start)
  range = backward == QTRUE ? base : stop
  r = onig_search(zr_regexp_reg_for(re, str), base, stop, from, range, region, Machine.i32(0))
  code = Machine.word(r)
  if code >= 2147483648
    onig_region_free(region, Machine.i32(1))
    return Machine.value(QNIL)
  end
  out = zr_region_offsets(region, code)
  onig_region_free(region, Machine.i32(1))
  out
end

# Match `str` at exactly byte `start`, as `\A`-anchored would.
sig [Value, Value, Value] => Value
machine def zr_regexp_match_at(re, str, start)
  region = onig_region_new()
  base = RString.ptr(str)
  stop = base + RString.len(str)
  r = onig_match(zr_regexp_reg_for(re, str), base, stop, base + zr_fix2long(start), region, Machine.i32(0))
  code = Machine.word(r)
  if code >= 2147483648
    onig_region_free(region, Machine.i32(1))
    return Machine.value(QNIL)
  end
  out = zr_region_offsets(region, zr_fix2long(start))
  onig_region_free(region, Machine.i32(1))
  out
end

sig [Ptr, Word] => Value
machine def zr_region_offsets(region, position)
  n = Machine.word(Machine.load32(region, 4))
  begs = Machine.ptr(Machine.load64(region, 8))
  ends = Machine.ptr(Machine.load64(region, 16))
  out = zr_ary_new(n * 2 + 1)
  zr_ary_push(out, zr_fix(position))
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
  zr_mark(RRegexp.text(re))
  zr_mark(RRegexp.names(re))
end

sig [Value] => Void
machine def zr_release_regexp(re)
  if RRegexp.reg(re) != 0
    onig_free(RRegexp.reg(re))
  end
  if RRegexp.alt(re) != 0
    onig_free(RRegexp.alt(re))
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

# `$_`, the last line read, lives beside `$~`.
sig [Value] => Value
machine def zr_lastline_set(v)
  home = zr_backref_home()
  if home != 0
    Frame.set_lastline(home, v)
  end
  v
end

sig [] => Value
machine def zr_lastline_get
  home = zr_backref_home()
  home == 0 ? Machine.value(QNIL) : Frame.lastline(home)
end
