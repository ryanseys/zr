# Regexp on the Onigmo matcher of the kernel (lib/zr/runtime/kernel/onig_*.rb).
# A T_REGEXP cell contains the program that the core compiled. A search
# returns the byte offsets of all groups. The last match (`$~`) is in
# the frame record of the calling method, as in CRuby.
#
# The matcher, its encoders, tables and stack (lib/zr/runtime/kernel/onig_*.rb)
# and the parser, tree setup, optimizer and compiler of the core
# (lib/zr/runtime/core/regexp/onig/*) are Onigmo, the regular expression engine
# of CRuby 4.0.7, written again in Ruby:
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

module Zr::Kern
  # `program` is the pattern compiled for the encoding of the source, as
  # the program String of lib/zr/runtime/core/regexp/onig/program.rb. `alt` is
  # nil or the Hash of programs that Regexp#program_for compiled again for
  # subjects in other encodings. `names` contains
  # [[name, [group numbers]], ...]. `limit` is the timeout of the pattern
  # in nanoseconds, or 0 for none.
  RRegexp = layout basic: RBasic, source: Value, options: Word, program: Value, names: Value, alt: Value, limit: Word
  T_REGEXP = 31
  G_REGEXP = 42
  G_REGEXP_LITERALS = 43

  # `Regexp.allocate`: a regexp cell with no pattern. All readers report
  # it as uninitialized until an `initialize` puts a pattern in it. This
  # is CRuby's rb_reg_s_alloc. A Regexp subclass also allocates with it,
  # so the empty cell that its initialize fills is a real regexp from the
  # start.
  sig [Value] => Value
  def zr_regexp_alloc(klass)
    re = zr_alloc(T_REGEXP, klass, RRegexp.size)
    RRegexp.set_source(re, Machine.value(QNIL))
    RRegexp.set_options(re, 0)
    RRegexp.set_names(re, Machine.value(QNIL))
    RRegexp.set_program(re, Machine.value(QNIL))
    RRegexp.set_alt(re, Machine.value(QNIL))
    RRegexp.set_limit(re, 0)
    re
  end

  # Copies the pattern of `other` into the empty cell `re`: its source,
  # options, names and program. These never change, so the copy shares
  # them. The copy compiles its own programs for other encodings.
  sig [Value, Value] => Value
  def zr_regexp_copy_from(re, other)
    RRegexp.set_source(re, RRegexp.source(other))
    RRegexp.set_options(re, RRegexp.options(other))
    RRegexp.set_names(re, RRegexp.names(other))
    RRegexp.set_program(re, RRegexp.program(other))
    RRegexp.set_alt(re, Machine.value(QNIL))
    RRegexp.set_limit(re, RRegexp.limit(other))
    re
  end

  # The compile of `source` under the option `bits` that the host makes
  # with CRuby, or nil (lib/zr/machine/host/walk/regexps.rb). A binary has
  # none: the core compiles each pattern itself (`Regexp.compiled`).
  sig [Value, Value] => Value
  def zr_regexp_host_compile(source, bits)
    Machine.value(QNIL)
  end

  # Puts the compiled `program` into the empty cell `re`, with the
  # `options` (Ruby's bits) that it was compiled with, `shown` (the text
  # as written, which the Regexp reports as its source) and its `names`.
  sig [Value, Value, Value, Value, Value] => Value
  def zr_regexp_seat(re, program, shown, options, names)
    RRegexp.set_program(re, program)
    RRegexp.set_alt(re, Machine.value(QNIL))
    RRegexp.set_source(re, shown)
    RRegexp.set_options(re, zr_fix2long(options))
    RRegexp.set_names(re, names)
    re
  end

  # The programs compiled for other encodings: nil or a Hash.
  sig [Value] => Value
  def zr_regexp_alt(re)
    RRegexp.alt(re)
  end

  sig [Value, Value] => Value
  def zr_regexp_alt_set(re, programs)
    RRegexp.set_alt(re, programs)
    programs
  end

  # The number of groups that the program captures.
  sig [Value] => Value
  def zr_regexp_captures(re)
    zr_fix(OnigProg.num_mem(RString.ptr(RRegexp.program(re))))
  end

  # The named groups: [[name, [group numbers]], ...].
  sig [Value] => Value
  def zr_regexp_names(re)
    RRegexp.names(re)
  end

  # The region that a search of `program` fills: 2 * (num_mem + 1) words,
  # in the scratch buffer that all searches share. `zr_regexp_region_free`
  # releases it.
  sig [Ptr] => Ptr
  def zr_regexp_region_new(prog)
    zr_onig_scratch(0, (OnigProg.num_mem(prog) + 1) * 16)
  end

  sig [Ptr] => Void
  def zr_regexp_region_free(region)
    zr_onig_scratch_free(0, region)
  end

  # Searches `str` from byte `start` (backward to it when `backward`).
  # Returns nil, or [position, begin0, end0, begin1, end1, ...]: the byte
  # where the match started (before a `\K`), then the offsets of each
  # group, with -1 for a group that did not match. `program` is the one
  # that Regexp#program_for chose, or nil for the pattern's own.
  sig [Value, Value, Value, Value, Value] => Value
  def zr_regexp_search(re, program, str, start, backward)
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

  # The result of a search that found nothing (nil), or that the time
  # limit stopped.
  sig [Word] => Value
  def zr_regexp_failed(r)
    if r != ONIGERR_TIMEOUT
      return Machine.value(QNIL)
    end
    error = zr_const_get_at(zr_core_class(Machine.id(:Regexp)), Machine.id(:TimeoutError))
    return error if error == QUNDEF
    zr_raise_msg(error, Machine.bytes("regexp match timeout"), 20)
  end

  # Matches `str` at exactly byte `start`, as a `\A` anchor would.
  sig [Value, Value, Value, Value] => Value
  def zr_regexp_match_at(re, program, str, start)
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

  # Makes [position, beg0, end0, ...] from a region of num_mem + 1 groups.
  sig [Ptr, Word, Word] => Value
  def zr_region_offsets(region, num_mem, position)
    zr_region_offsets_after(region, num_mem, position, 0)
  end

  # The same offsets, for a match whose text starts `base` bytes into the
  # String, counted from the start of the String. -1 stays -1.
  sig [Ptr, Word, Word, Word] => Value
  def zr_region_offsets_after(region, num_mem, position, base)
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

  # StringScanner's onig_match and onig_search. The text starts `base`
  # bytes into `str` (the scan pointer, or 0 for a fixed anchor). The
  # match is tried at byte `start`, or searched for from there to the end.
  # Offsets count from the start of the String.
  sig [Value, Value, Value, Value, Value, Value] => Value
  def zr_regexp_scan_in(re, program, str, base, start, search)
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

  # The maximum time in nanoseconds for a match of `re`: its own timeout,
  # else Regexp.timeout, else 0 for no limit.
  sig [Value] => Word
  def zr_regexp_limit_for(re)
    RRegexp.limit(re) != 0 ? RRegexp.limit(re) : Machine.load64(Machine.static(:regexp_limit, 8), 0)
  end

  sig [Value] => Void
  def zr_mark_regexp(re)
    zr_mark(RRegexp.source(re))
    zr_mark(RRegexp.names(re))
    zr_mark(RRegexp.program(re))
    zr_mark(RRegexp.alt(re))
  end

  # A regexp has no memory outside the heap.
  sig [Value] => Void
  def zr_release_regexp(re)
  end

  sig [Value] => Value
  def zr_regexp_source(re)
    RRegexp.source(re)
  end

  sig [Value] => Value
  def zr_regexp_options(re)
    zr_fix(RRegexp.options(re))
  end

  # `/#{x}/o`: the regexp of the site, made once. It is nil until the
  # site runs.
  sig [Word] => Value
  def zr_regexp_once(index)
    zr_site_literal(G_REGEXP_LITERALS, index)
  end

  sig [Word, Value] => Value
  def zr_regexp_once_set(index, re)
    zr_site_literal_set(G_REGEXP_LITERALS, index, re)
    re
  end

  # A regexp literal. The core compiles it the first time its site runs.
  # After that, the site gets the same frozen object from the literal
  # table, at the index of the site.
  sig [Word, Ptr, Word, Word, Word] => Value
  def zr_regexp_literal(index, bytes, len, options, pinned)
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

  # Sets a timeout in nanoseconds (0 for none): the timeout of `re`, or
  # Regexp.timeout when `re` is nil. Returns the timeout.
  sig [Value, Value] => Value
  def zr_regexp_limit_set(re, nanoseconds)
    if re == QNIL
      Machine.store64(Machine.static(:regexp_limit, 8), 0, zr_fix2long(nanoseconds))
    else
      RRegexp.set_limit(re, zr_fix2long(nanoseconds))
    end
    nanoseconds
  end

  sig [Value] => Value
  def zr_regexp_limit(re)
    zr_fix(re == QNIL ? Machine.load64(Machine.static(:regexp_limit, 8), 0) : RRegexp.limit(re))
  end

  # Returns the frame record whose `$~` the running code sees. A block
  # uses the record of its method, an eval uses the scope that called it,
  # and a core method uses the record of its caller.
  sig [] => Ptr
  def zr_backref_home
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

  # The `$~` and `$_` of the frame, in an Array that is made at the first
  # write of one of them.
  sig [Ptr] => Value
  def zr_svars(home)
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
  def zr_svar_get(home, i)
    cell = Frame.svars(home)
    cell == QNIL ? Machine.value(QNIL) : zr_ary_at(cell, i)
  end

  sig [Value] => Value
  def zr_backref_set(v)
    home = zr_backref_home()
    if home != 0
      zr_ary_store(zr_svars(home), 0, v)
    end
    v
  end

  # `$~ = v` from a program: `v` must be a MatchData or nil, as the hook
  # of Kernel checks.
  sig [Value] => Value
  def zr_backref_assign(v)
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
  def zr_backref_get
    home = zr_backref_home()
    home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 0)
  end

  # The registers of a match, read as CRuby's rb_reg_nth_match and
  # related functions read them. `$1`, `$&`, `` $` ``, `$'`, `$+` and the
  # `` of a replacement never call MatchData methods that a user defines.
  # `m` is a MatchData or nil. Its offsets are
  # `[position, begin0, end0, begin1, end1, ...]`, as the search made them
  # (lib/zr/runtime/core/regexp.rb, MatchData#matched).
  sig [Value, Value] => Value
  def zr_match_nth(m, n)
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

  # `$+`: the last group that matched, or nil when no group matched.
  sig [Value] => Value
  def zr_match_last(m)
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
  def zr_match_pre(m)
    if m == QNIL
      return Machine.value(QNIL)
    end
    zr_str_byteslice(zr_ivar_get(m, Machine.id(:string)), zr_fix(0), zr_ary_at(zr_ivar_get(m, Machine.id(:offsets)), 1))
  end

  # `$'`: the text after the match.
  sig [Value] => Value
  def zr_match_post(m)
    if m == QNIL
      return Machine.value(QNIL)
    end
    s = zr_ivar_get(m, Machine.id(:string))
    e = zr_fix2long(zr_ary_at(zr_ivar_get(m, Machine.id(:offsets)), 2))
    zr_str_byteslice(s, zr_fix(e), zr_fix(RString.len(s) - e))
  end

  # `$_`, the last line read, is next to `$~`.
  sig [Value] => Value
  def zr_lastline_set(v)
    home = zr_backref_home()
    if home != 0
      zr_ary_store(zr_svars(home), 1, v)
    end
    v
  end

  sig [] => Value
  def zr_lastline_get
    home = zr_backref_home()
    home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 1)
  end
end
