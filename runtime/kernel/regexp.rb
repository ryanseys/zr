# Regexp over the kernel's Onigmo matcher (runtime/kernel/onig_*.rb): a
# T_REGEXP cell holds the program the core compiled; a search answers
# the byte offsets of every group. The last match (`$~`) lives in the
# frame record of the method that asked, as CRuby keeps it.
#
# The matcher, its encoders, tables and stack (runtime/kernel/onig_*.rb) and
# the core's parser, tree setup, optimizer and compiler
# (runtime/core/regexp/onig/*) are Onigmo, the regular expression engine of
# CRuby 4.0.6, written again in Ruby:
#
#   Copyright (c) 2002-2013 K.Kosako <sndgk393 AT ybb DOT ne DOT jp>
#   Copyright (c) 2011-2016 K.Takata <kentkt AT csc DOT jp>
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions
#   are met:
#   1. Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#   2. Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#
#   THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
#   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#   ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
#   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
#   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
#   OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
#   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#   LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
#   OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#   SUCH DAMAGE.

# `program` is the pattern the source's own encoding built, as the
# program String of runtime/core/regexp/onig/program.rb; `alt` is nil or the
# Hash of programs Regexp#program_for compiled again for subjects of
# other encodings. `names` holds [[name, [group numbers]], ...].
# `limit` is the pattern's own timeout in nanoseconds, 0 for none.
Machine.struct :RRegexp, basic: RBasic, source: Value, options: Word, program: Value, names: Value, alt: Value, limit: Word
T_REGEXP = 31
G_REGEXP = 42
G_REGEXP_LITERALS = 43

# `Regexp.allocate`: a regexp cell with no pattern in it, which every
# reader names as uninitialized until an `initialize` seats one. This
# is CRuby's rb_reg_s_alloc, and a Regexp subclass allocates it too, so
# the husk its own initialize fills is a real regexp from the start.
sig [Value] => Value
machine def zr_regexp_alloc(klass)
  re = zr_alloc(T_REGEXP, klass, RRegexp.size)
  RRegexp.set_source(re, Machine.value(QNIL))
  RRegexp.set_options(re, 0)
  RRegexp.set_names(re, Machine.value(QNIL))
  RRegexp.set_program(re, Machine.value(QNIL))
  RRegexp.set_alt(re, Machine.value(QNIL))
  RRegexp.set_limit(re, 0)
  re
end

# The pattern `other` holds, in the husk `re`: its source, options,
# names and program, which never change, so the copy shares them. The
# programs for other encodings are the copy's own to compile.
sig [Value, Value] => Value
machine def zr_regexp_copy_from(re, other)
  RRegexp.set_source(re, RRegexp.source(other))
  RRegexp.set_options(re, RRegexp.options(other))
  RRegexp.set_names(re, RRegexp.names(other))
  RRegexp.set_program(re, RRegexp.program(other))
  RRegexp.set_alt(re, Machine.value(QNIL))
  RRegexp.set_limit(re, RRegexp.limit(other))
  re
end

# The compiled `program`, seated in the husk `re` with the `options`
# (Ruby's bits) it compiled under, `shown` (the text as written, which
# the Regexp reports as its source) and its `names`.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_regexp_seat(re, program, shown, options, names)
  RRegexp.set_program(re, program)
  RRegexp.set_alt(re, Machine.value(QNIL))
  RRegexp.set_source(re, shown)
  RRegexp.set_options(re, zr_fix2long(options))
  RRegexp.set_names(re, names)
  re
end

# The programs compiled for other encodings: nil or a Hash.
sig [Value] => Value
machine def zr_regexp_alt(re)
  RRegexp.alt(re)
end

sig [Value, Value] => Value
machine def zr_regexp_alt_set(re, programs)
  RRegexp.set_alt(re, programs)
  programs
end

# The number of groups the program captures.
sig [Value] => Value
machine def zr_regexp_captures(re)
  zr_fix(OnigProg.num_mem(RString.ptr(RRegexp.program(re))))
end

# The named groups: [[name, [group numbers]], ...].
sig [Value] => Value
machine def zr_regexp_names(re)
  RRegexp.names(re)
end

# The region a search of `program` fills: 2 * (num_mem + 1) words, in
# the scratch buffer every search shares, given back by
# `zr_regexp_region_free`.
sig [Ptr] => Ptr
machine def zr_regexp_region_new(prog)
  zr_onig_scratch(0, (OnigProg.num_mem(prog) + 1) * 16)
end

sig [Ptr] => Void
machine def zr_regexp_region_free(region)
  zr_onig_scratch_free(0, region)
end

# Search `str` from byte `start` (backwards to it when `backward`):
# nil, or [position, begin0, end0, begin1, end1, ...]: the byte the
# match started at (before a `\K`), then every group's offsets, -1
# for a group that did not take part. `program` is the one
# Regexp#program_for chose, nil for the pattern's own.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_regexp_search(re, program, str, start, backward)
  if program == QNIL
    program = RRegexp.program(re)
  end
  prog = RString.ptr(program)
  region = zr_regexp_region_new(prog)
  base = RString.ptr(str)
  stop = base + RString.len(str)
  from = base + zr_fix2long(start)
  range = backward == QTRUE ? base : stop
  r = zr_onig_search(prog, base, stop, from, range, region, zr_regexp_limit_for(re))
  if r < 0
    zr_regexp_region_free(region)
    return zr_regexp_failed(r)
  end
  out = zr_region_offsets(region, OnigProg.num_mem(prog), r)
  zr_regexp_region_free(region)
  out
end

# A search that found nothing (nil), or one the time limit stopped.
sig [Word] => Value
machine def zr_regexp_failed(r)
  if r != ONIGERR_TIMEOUT
    return Machine.value(QNIL)
  end
  error = zr_const_get_at(zr_core_class(Machine.id(:Regexp)), Machine.id(:TimeoutError))
  return error if error == QUNDEF
  zr_raise_msg(error, Machine.bytes("regexp match timeout"), 20)
end

# Match `str` at exactly byte `start`, as `\A`-anchored would.
sig [Value, Value, Value, Value] => Value
machine def zr_regexp_match_at(re, program, str, start)
  if program == QNIL
    program = RRegexp.program(re)
  end
  prog = RString.ptr(program)
  region = zr_regexp_region_new(prog)
  base = RString.ptr(str)
  stop = base + RString.len(str)
  r = zr_onig_match(prog, base, stop, base + zr_fix2long(start), region, zr_regexp_limit_for(re))
  if r < 0
    zr_regexp_region_free(region)
    return zr_regexp_failed(r)
  end
  out = zr_region_offsets(region, OnigProg.num_mem(prog), zr_fix2long(start))
  zr_regexp_region_free(region)
  out
end

# [position, beg0, end0, ...] from a region of num_mem + 1 groups.
sig [Ptr, Word, Word] => Value
machine def zr_region_offsets(region, num_mem, position)
  zr_region_offsets_after(region, num_mem, position, 0)
end

# The same offsets from a match whose text began `base` bytes into the
# String, counted from the String's start; -1 stays -1.
sig [Ptr, Word, Word, Word] => Value
machine def zr_region_offsets_after(region, num_mem, position, base)
  n = num_mem + 1
  out = zr_ary_new(n * 2 + 1)
  zr_ary_push(out, zr_fix(position + base))
  i = 0
  while i < n
    beg = Machine.word(Machine.load64(region + (i * 16), 0))
    stop = Machine.word(Machine.load64(region + (i * 16), 8))
    zr_ary_push(out, zr_fix(beg < 0 ? beg : beg + base))
    zr_ary_push(out, zr_fix(stop < 0 ? stop : stop + base))
    i += 1
  end
  out
end

# StringScanner's onig_match and onig_search: the text starts `base`
# bytes into `str` (the scan pointer, or 0 for a fixed anchor), and the
# match is tried at byte `start`, or searched for from it to the end.
# Offsets count from the String's start.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_regexp_scan_in(re, program, str, base, start, search)
  if program == QNIL
    program = RRegexp.program(re)
  end
  prog = RString.ptr(program)
  region = zr_regexp_region_new(prog)
  origin = RString.ptr(str) + zr_fix2long(base)
  stop = RString.ptr(str) + RString.len(str)
  at = RString.ptr(str) + zr_fix2long(start)
  r = 0
  if search == QTRUE
    r = zr_onig_search(prog, origin, stop, at, stop, region, zr_regexp_limit_for(re))
  else
    r = zr_onig_match(prog, origin, stop, at, region, zr_regexp_limit_for(re))
  end
  if r < 0
    zr_regexp_region_free(region)
    return zr_regexp_failed(r)
  end
  position = search == QTRUE ? r : zr_fix2long(start) - zr_fix2long(base)
  out = zr_region_offsets_after(region, OnigProg.num_mem(prog), position, zr_fix2long(base))
  zr_regexp_region_free(region)
  out
end

# The nanoseconds a match of `re` may take: its own timeout, else
# Regexp.timeout, else 0 for no limit.
sig [Value] => Word
machine def zr_regexp_limit_for(re)
  RRegexp.limit(re) != 0 ? RRegexp.limit(re) : Machine.load64(Machine.static(:regexp_limit, 8), 0)
end

sig [Value] => Void
machine def zr_mark_regexp(re)
  zr_mark(RRegexp.source(re))
  zr_mark(RRegexp.names(re))
  zr_mark(RRegexp.program(re))
  zr_mark(RRegexp.alt(re))
end

# A regexp holds nothing outside the heap.
sig [Value] => Void
machine def zr_release_regexp(re)
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

# `/#{x}/o`: the site's regexp, made once. nil until the site has run.
sig [Word] => Value
machine def zr_regexp_once(index)
  zr_site_literal(G_REGEXP_LITERALS, index)
end

sig [Word, Value] => Value
machine def zr_regexp_once_set(index, re)
  zr_site_literal_set(G_REGEXP_LITERALS, index, re)
  re
end

# A regexp literal: compiled by the core the first time its site runs,
# then the same frozen object, held in the literal table by the site's
# index.
sig [Word, Ptr, Word, Word, Word] => Value
machine def zr_regexp_literal(index, bytes, len, options, pinned)
  re = zr_site_literal(G_REGEXP_LITERALS, index)
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
  zr_site_literal_set(G_REGEXP_LITERALS, index, re)
  re
end

# A timeout in nanoseconds, 0 for none: `re`'s own, or Regexp.timeout
# where `re` is nil. The answer is the timeout set.
sig [Value, Value] => Value
machine def zr_regexp_limit_set(re, nanoseconds)
  if re == QNIL
    Machine.store64(Machine.static(:regexp_limit, 8), 0, zr_fix2long(nanoseconds))
  else
    RRegexp.set_limit(re, zr_fix2long(nanoseconds))
  end
  nanoseconds
end

sig [Value] => Value
machine def zr_regexp_limit(re)
  zr_fix(re == QNIL ? Machine.load64(Machine.static(:regexp_limit, 8), 0) : RRegexp.limit(re))
end

# The frame record whose `$~` the running code sees: a block's is its
# method's, an eval's is the scope that asked, and a core method's is
# its caller's.
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
    elsif (FrameMeta.kind(meta) == KIND_BLOCK || FrameMeta.kind(meta) == KIND_HIDDEN || FrameMeta.kind(meta) == KIND_EVAL) && FrameMeta.parent(meta) != 0
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

# The frame's `$~` and `$_`, in an Array made the first time one is
# written under it.
sig [Ptr] => Value
machine def zr_svars(home)
  cell = Frame.svars(home)
  if cell == QNIL
    cell = zr_ary_new(2)
    zr_ary_push(cell, Machine.value(QNIL))
    zr_ary_push(cell, Machine.value(QNIL))
    Frame.set_svars(home, cell)
  end
  cell
end

sig [Ptr, Word] => Value
machine def zr_svar_get(home, i)
  cell = Frame.svars(home)
  cell == QNIL ? Machine.value(QNIL) : zr_ary_at(cell, i)
end

sig [Value] => Value
machine def zr_backref_set(v)
  home = zr_backref_home()
  if home != 0
    zr_ary_store(zr_svars(home), 0, v)
  end
  v
end

# `$~ = v` as a program writes it: a MatchData or nil, as Kernel's hook
# checks.
sig [Value] => Value
machine def zr_backref_assign(v)
  argv = Machine.slot(24)
  Machine.store64(argv, 0, Machine.word(zr_sym(Machine.id(:$~))))
  Machine.store64(argv, 8, Machine.word(zr_sym(Machine.id(:$~))))
  Machine.store64(argv, 16, Machine.word(v))
  if zr_send(zr_global(G_KERNEL), Machine.id(:hooked_global), 3, argv) == QUNDEF
    return Machine.value(QUNDEF)
  end
  zr_backref_set(v)
end

sig [] => Value
machine def zr_backref_get
  home = zr_backref_home()
  home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 0)
end

# A match's registers, read as CRuby's rb_reg_nth_match and its kin
# read them: `$1`, `$&`, `` $` ``, `$'`, `$+` and a replacement's ``
# never ask a user's MatchData methods. `m` is a MatchData or nil. Its
# offsets are `[position, begin0, end0, begin1, end1, ...]`, as the
# search made them (runtime/core/regexp.rb, MatchData#matched).
sig [Value, Value] => Value
machine def zr_match_nth(m, n)
  if m == QNIL
    return Machine.value(QNIL)
  end
  offsets = zr_ivar_get(m, Machine.id(:offsets))
  i = zr_fix2long(n) * 2 + 1
  if i < 1 || i >= RArray.len(offsets)
    return Machine.value(QNIL)
  end
  b = zr_fix2long(zr_ary_at(offsets, i))
  if b < 0
    return Machine.value(QNIL)
  end
  zr_str_byteslice(zr_ivar_get(m, Machine.id(:string)), zr_fix(b), zr_fix(zr_fix2long(zr_ary_at(offsets, i + 1)) - b))
end

# `$+`: the last group that took part, nil when none did.
sig [Value] => Value
machine def zr_match_last(m)
  if m == QNIL
    return Machine.value(QNIL)
  end
  offsets = zr_ivar_get(m, Machine.id(:offsets))
  i = (RArray.len(offsets) - 1) / 2 - 1
  while i > 0 && zr_fix2long(zr_ary_at(offsets, i * 2 + 1)) < 0
    i -= 1
  end
  if i == 0
    return Machine.value(QNIL)
  end
  zr_match_nth(m, zr_fix(i))
end

# `` $` ``: the text before the match.
sig [Value] => Value
machine def zr_match_pre(m)
  if m == QNIL
    return Machine.value(QNIL)
  end
  zr_str_byteslice(zr_ivar_get(m, Machine.id(:string)), zr_fix(0), zr_ary_at(zr_ivar_get(m, Machine.id(:offsets)), 1))
end

# `$'`: the text after the match.
sig [Value] => Value
machine def zr_match_post(m)
  if m == QNIL
    return Machine.value(QNIL)
  end
  s = zr_ivar_get(m, Machine.id(:string))
  e = zr_fix2long(zr_ary_at(zr_ivar_get(m, Machine.id(:offsets)), 2))
  zr_str_byteslice(s, zr_fix(e), zr_fix(RString.len(s) - e))
end

# `$_`, the last line read, lives beside `$~`.
sig [Value] => Value
machine def zr_lastline_set(v)
  home = zr_backref_home()
  if home != 0
    zr_ary_store(zr_svars(home), 1, v)
  end
  v
end

sig [] => Value
machine def zr_lastline_get
  home = zr_backref_home()
  home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 1)
end
