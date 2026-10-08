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
  #
  # The first fields are CRuby's struct RRegexp, which C reads inline:
  # `ptr` (RREGEXP_PTR) is the regex_t that C passes back to onig_search
  # and the like (capi/regex.rb), here the cell's own address; `source` is
  # RREGEXP_SRC; `usecnt` counts C matches in progress.
  class RRegexp < Layout
    attr_reader :basic #: RBasic
    attr_accessor :ptr #: word
    attr_accessor :source #: value
    attr_accessor :usecnt #: word
    attr_accessor :options #: word
    attr_accessor :program #: value
    attr_accessor :names #: value
    attr_accessor :alt #: value
    attr_accessor :limit #: word
  end

  T_REGEXP = 6
  G_REGEXP = 42
  G_REGEXP_LITERALS = 43

  # `Regexp.allocate`: a regexp cell with no pattern. All readers report
  # it as uninitialized until an `initialize` puts a pattern in it. This
  # is CRuby's rb_reg_s_alloc. A Regexp subclass also allocates with it,
  # so the empty cell that its initialize fills is a real regexp from the
  # start.
  #: (value) -> value
  def zr_regexp_alloc(klass)
    re = zr_alloc(T_REGEXP, klass, RRegexp.size)
    RRegexp[re].ptr = Machine.word(re)
    RRegexp[re].usecnt = 0
    RRegexp[re].source = Machine.value(QNIL)
    RRegexp[re].options = 0
    RRegexp[re].names = Machine.value(QNIL)
    RRegexp[re].program = Machine.value(QNIL)
    RRegexp[re].alt = Machine.value(QNIL)
    RRegexp[re].limit = 0
    re
  end

  # Copies the pattern of `other` into the empty cell `re`: its source,
  # options, names and program. These never change, so the copy shares
  # them. The copy compiles its own programs for other encodings.
  #: (value, value) -> value
  def zr_regexp_copy_from(re, other)
    RRegexp[re].source = RRegexp[other].source
    RRegexp[re].options = RRegexp[other].options
    RRegexp[re].names = RRegexp[other].names
    RRegexp[re].program = RRegexp[other].program
    RRegexp[re].alt = Machine.value(QNIL)
    RRegexp[re].limit = RRegexp[other].limit
    re
  end

  # The compile of `source` under the option `bits` that the host makes
  # with CRuby, or nil (lib/zr/machine/host/walk/regexps.rb). A binary has
  # none: the core compiles each pattern itself (`Regexp.compiled`).
  #: (value, value) -> value
  def zr_regexp_host_compile(source, bits)
    Machine.value(QNIL)
  end

  # Puts the compiled `program` into the empty cell `re`, with the
  # `options` (Ruby's bits) that it was compiled with, `shown` (the text
  # as written, which the Regexp reports as its source) and its `names`.
  #: (value, value, value, value, value) -> value
  def zr_regexp_seat(re, program, shown, options, names)
    RRegexp[re].program = program
    RRegexp[re].alt = Machine.value(QNIL)
    RRegexp[re].source = shown
    RRegexp[re].options = zr_fix2long(options)
    RRegexp[re].names = names
    re
  end

  # The programs compiled for other encodings: nil or a Hash.
  #: (value) -> value
  def zr_regexp_alt(re)
    RRegexp[re].alt
  end

  #: (value, value) -> value
  def zr_regexp_alt_set(re, programs)
    RRegexp[re].alt = programs
    programs
  end

  # The number of groups that the program captures.
  #: (value) -> value
  def zr_regexp_captures(re)
    zr_fix(OnigProg[RString[RRegexp[re].program].ptr].num_mem)
  end

  # The named groups: [[name, [group numbers]], ...].
  #: (value) -> value
  def zr_regexp_names(re)
    RRegexp[re].names
  end

  # The region that a search of `program` fills: 2 * (num_mem + 1) words,
  # in the scratch buffer that all searches share. `zr_regexp_region_free`
  # releases it.
  #: (ptr) -> ptr
  def zr_regexp_region_new(prog)
    zr_onig_scratch(0, (OnigProg[prog].num_mem + 1) * 16)
  end

  #: (ptr) -> void
  def zr_regexp_region_free(region)
    zr_onig_scratch_free(0, region)
  end

  # Searches `str` from byte `start` (backward to it when `backward`).
  # Returns nil, or [position, begin0, end0, begin1, end1, ...]: the byte
  # where the match started (before a `\K`), then the offsets of each
  # group, with -1 for a group that did not match. `program` is the one
  # that Regexp#program_for chose, or nil for the pattern's own.
  #: (value, value, value, value, value) -> value
  def zr_regexp_search(re, program, str, start, backward)
    if program == QNIL
      program = RRegexp[re].program
    end
    prog = RString[program].ptr
    region = zr_regexp_region_new(prog)
    base = RString[str].ptr
    stop = base + RString[str].len
    from = base + zr_fix2long(start)
    range = backward == QTRUE ? base : stop
    r = zr_onig_search(prog, base, stop, from, range, region, zr_regexp_limit_for(re))
    if r < 0
      zr_regexp_region_free(region)
      return zr_regexp_failed(r)
    end
    out = zr_region_offsets(region, OnigProg[prog].num_mem, r)
    zr_regexp_region_free(region)
    out
  end

  # The result of a search that found nothing (nil), or that the time
  # limit stopped.
  #: (word) -> value
  def zr_regexp_failed(r)
    if r != ONIGERR_TIMEOUT
      return Machine.value(QNIL)
    end
    error = zr_const_get_at(zr_core_class(Machine.id(:Regexp)), Machine.id(:TimeoutError))
    return error if error == QUNDEF
    zr_raise_msg(error, Machine.bytes("regexp match timeout"), 20)
  end

  # Matches `str` at exactly byte `start`, as a `\A` anchor would.
  #: (value, value, value, value) -> value
  def zr_regexp_match_at(re, program, str, start)
    if program == QNIL
      program = RRegexp[re].program
    end
    prog = RString[program].ptr
    region = zr_regexp_region_new(prog)
    base = RString[str].ptr
    stop = base + RString[str].len
    r = zr_onig_match(prog, base, stop, base + zr_fix2long(start), region, zr_regexp_limit_for(re))
    if r < 0
      zr_regexp_region_free(region)
      return zr_regexp_failed(r)
    end
    out = zr_region_offsets(region, OnigProg[prog].num_mem, zr_fix2long(start))
    zr_regexp_region_free(region)
    out
  end

  # Makes [position, beg0, end0, ...] from a region of num_mem + 1 groups.
  #: (ptr, word, word) -> value
  def zr_region_offsets(region, num_mem, position)
    zr_region_offsets_after(region, num_mem, position, 0)
  end

  # The same offsets, for a match whose text starts `base` bytes into the
  # String, counted from the start of the String. -1 stays -1.
  #: (ptr, word, word, word) -> value
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
  #: (value, value, value, value, value, value) -> value
  def zr_regexp_scan_in(re, program, str, base, start, search)
    if program == QNIL
      program = RRegexp[re].program
    end
    prog = RString[program].ptr
    region = zr_regexp_region_new(prog)
    origin = RString[str].ptr + zr_fix2long(base)
    stop = RString[str].ptr + RString[str].len
    at = RString[str].ptr + zr_fix2long(start)
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
    out = zr_region_offsets_after(region, OnigProg[prog].num_mem, position, zr_fix2long(base))
    zr_regexp_region_free(region)
    out
  end

  # The maximum time in nanoseconds for a match of `re`: its own timeout,
  # else Regexp.timeout, else 0 for no limit.
  #: (value) -> word
  def zr_regexp_limit_for(re)
    RRegexp[re].limit != 0 ? RRegexp[re].limit : Machine.load64(Machine.static(:regexp_limit, 8), 0)
  end

  #: (value) -> void
  def zr_mark_regexp(re)
    zr_mark(RRegexp[re].source)
    zr_mark(RRegexp[re].names)
    zr_mark(RRegexp[re].program)
    zr_mark(RRegexp[re].alt)
  end

  # A regexp has no memory outside the heap.
  #: (value) -> void
  def zr_release_regexp(re)
  end

  #: (value) -> value
  def zr_regexp_source(re)
    RRegexp[re].source
  end

  #: (value) -> value
  def zr_regexp_options(re)
    zr_fix(RRegexp[re].options)
  end

  # `/#{x}/o`: the regexp of the site, made once. It is nil until the
  # site runs, and then the caller makes it. As in vm_once_dispatch, the
  # first fiber to run the site claims it: another fiber that runs the
  # site meanwhile waits for the regexp. The claim names the fiber and
  # the frame that runs the site. A frame that leaves before it makes the
  # regexp (a throw out of the interpolation) ends its claim, and the
  # next run makes the regexp again.
  #: (word) -> value
  def zr_regexp_once(index)
    while true
      kept = zr_site_literal(G_REGEXP_LITERALS, index)
      if kept != QNIL
        return kept
      end
      claim = zr_site_literal(G_REGEXP_LITERALS, zr_regexp_once_claim_key(index))
      if claim == QNIL || zr_ary_at(claim, 0) == zr_fiber_current() || !zr_regexp_once_making_p(claim)
        break
      end
      # Thread.pass would leave a sleeping maker asleep: a tick of sleep
      # lets the scheduler wake it.
      tick = Machine.slot(8)
      Machine.store64(tick, 0, Machine.word(zr_float_new(Machine.f64(ONCE_WAIT_BITS))))
      r = zr_send(zr_fiber_current(), Machine.id(:sleep), 1, tick)
      return r if r == QUNDEF
    end
    top = Task[zr_task()].top
    claim = zr_ary_new(3)
    zr_ary_push(claim, zr_fiber_current())
    zr_ary_push(claim, zr_fix(Machine.word(top)))
    zr_ary_push(claim, zr_fix(zr_frame_serial(top)))
    zr_site_literal_set(G_REGEXP_LITERALS, zr_regexp_once_claim_key(index), claim)
    Machine.value(QNIL)
  end

  # 0.001, the seconds that a fiber waits for a claim at a time.
  ONCE_WAIT_BITS = 0x3F50624DD2F1A9FC

  # The literal table keeps a site's claim at the negative key of the site.
  #: (word) -> word
  def zr_regexp_once_claim_key(index)
    0 - 1 - index
  end

  # Whether the frame of a claim is still on its fiber's stack.
  #: (value) -> bool
  def zr_regexp_once_making_p(claim)
    t = RFiber[zr_ary_at(claim, 0)].task
    if t == 0
      return false
    end
    frame = Machine.ptr(zr_fix2long(zr_ary_at(claim, 1)))
    serial = zr_fix2long(zr_ary_at(claim, 2))
    rec = Task[t].top
    while rec != 0
      if rec == frame
        return Frame[rec].serial == serial
      end
      rec = Frame[rec].prev
    end
    false
  end

  # Keeps the regexp that the site made, ends the claim, and returns the
  # site's regexp.
  #: (word, value) -> value
  def zr_regexp_once_set(index, re)
    zr_site_literal_set(G_REGEXP_LITERALS, zr_regexp_once_claim_key(index), Machine.value(QNIL))
    kept = zr_site_literal(G_REGEXP_LITERALS, index)
    if kept != QNIL
      return kept
    end
    zr_site_literal_set(G_REGEXP_LITERALS, index, re)
    re
  end

  # A regexp literal. The core compiles it the first time its site runs.
  # After that, the site gets the same frozen object from the literal
  # table, at the index of the site.
  #: (word, ptr, word, word, word) -> value
  def zr_regexp_literal(index, bytes, len, options, pinned)
    re = zr_site_literal(G_REGEXP_LITERALS, index)
    if re != QNIL
      return re
    end
    slot = Machine.slot(24)
    Machine.store64(slot, 0, Machine.word(zr_str_frozen(bytes, len)))
    Machine.store64(slot, 8, Machine.word(zr_fix(options)))
    Machine.store64(slot, 16, Machine.word(pinned < 0 ? Machine.value(QNIL) : zr_fix(pinned)))
    # The compile is the core's own work, which ruby does as it parses:
    # a core send, which no TracePoint sees.
    re = zr_dispatch(0, zr_global(G_REGEXP), Machine.id(:literal), 3, slot, SEND_CORE, Machine.value(QNIL))
    return re if re == QUNDEF
    RBasic[re].flags = RBasic[re].flags | FL_FREEZE
    zr_site_literal_set(G_REGEXP_LITERALS, index, re)
    re
  end

  # Sets a timeout in nanoseconds (0 for none): the timeout of `re`, or
  # Regexp.timeout when `re` is nil. Returns the timeout.
  #: (value, value) -> value
  def zr_regexp_limit_set(re, nanoseconds)
    if re == QNIL
      Machine.store64(Machine.static(:regexp_limit, 8), 0, zr_fix2long(nanoseconds))
    else
      RRegexp[re].limit = zr_fix2long(nanoseconds)
    end
    nanoseconds
  end

  #: (value) -> value
  def zr_regexp_limit(re)
    zr_fix(re == QNIL ? Machine.load64(Machine.static(:regexp_limit, 8), 0) : RRegexp[re].limit)
  end

  # Returns the frame record whose `$~` the running code sees. A block
  # uses the record of its method (a block of the core library too), an
  # eval uses the scope that called it, and a core method uses the record
  # of its caller, unless it matches
  # for its own work (`owns_backref`): then the match stays in its own
  # record and the program's `$~` is left alone, as a C function's
  # matches leave it.
  #: () -> ptr
  def zr_backref_home
    zr_backref_home_from(Task[zr_task()].top)
  end

  # The same, for code that runs in the frame `rec`.
  #: (ptr) -> ptr
  def zr_backref_home_from(rec)
    while rec != 0
      meta = Frame[rec].meta
      if meta == 0
        return rec
      end
      if FrameMeta[meta].file_len == 0 && FrameMeta[meta].owns_backref != 0
        return rec
      end
      # A block, the core's own included, uses the record of the method it
      # is written in, whoever calls it.
      if (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL) && FrameMeta[meta].parent != 0
        parent = FrameMeta[meta].parent
        up = Frame[rec].prev
        while up != 0 && Frame[up].meta != parent
          up = Frame[up].prev
        end
        if up == 0
          # The parent block has returned (a block made in it runs later):
          # $~ lives further out, as CRuby keeps it in the method's env.
          up = zr_backref_ancestor(rec, parent)
          if up == 0
            return zr_backref_elsewhere(rec, parent)
          end
        end
        rec = up
      elsif FrameMeta[meta].file_len == 0
        rec = Frame[rec].prev
      else
        return rec
      end
    end
    0
  end

  # The frame whose `$~` a block frame `rec` uses when the scope of its
  # parent `meta` is not on this stack. On the stack of a Thread or a
  # Fiber whose own block is in the same scope, it is the `$~` of that
  # stack, as CRuby's ec->root_svar. Else it is the `$~` that the block's
  # Proc kept (zr_proc_keep_svars), or one of the block's own.
  #: (ptr, ptr) -> ptr
  def zr_backref_elsewhere(rec, meta)
    # The stack's own block is its lowest block of a program: the core
    # frames that start a Thread or a Fiber are below it.
    root = Machine.ptr(0)
    at = Frame[rec].prev
    while at != 0
      if zr_block_frame_p(at) && FrameMeta[Frame[at].meta].file_len != 0
        root = at
      end
      at = Frame[at].prev
    end
    if root != 0 && zr_backref_scope_meta(FrameMeta[Frame[root].meta].parent) == zr_backref_scope_meta(meta)
      return root
    end
    zr_backref_kept(rec)
    rec
  end

  # The def, class body or file that the block or eval scope `meta` is in.
  #: (ptr) -> ptr
  def zr_backref_scope_meta(meta)
    while meta != 0 && (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL)
      meta = FrameMeta[meta].parent
    end
    meta
  end

  # A block frame uses the `$~` that its Proc kept, if it kept one.
  #: (ptr) -> void
  def zr_backref_kept(rec)
    if Frame[rec].svars != QNIL || Frame[rec].entry == 0
      return
    end
    p = Machine.value(Frame[rec].entry)
    if zr_special_p(p) || (RBasic[p].flags & FL_STACK) != 0 || zr_type(p) != T_PROC
      return
    end
    kept = zr_ivar_get(p, Machine.id(:__svars__))
    if kept != QNIL
      Frame[rec].svars = kept
    end
  end

  # The nearest live frame of a scope outside the block scope `meta`,
  # whose own frame has returned, or 0.
  #: (ptr, ptr) -> ptr
  def zr_backref_ancestor(rec, meta)
    while meta != 0 && (FrameMeta[meta].kind == KIND_BLOCK || FrameMeta[meta].kind == KIND_HIDDEN || FrameMeta[meta].kind == KIND_EVAL)
      meta = FrameMeta[meta].parent
      up = Frame[rec].prev
      while up != 0 && Frame[up].meta != meta
        up = Frame[up].prev
      end
      if up != 0
        return up
      end
    end
    0
  end

  # The `$~` and `$_` of the scope that called the core method that runs
  # now, as CRuby's ifunc keeps them in `svar_lep` when the method makes
  # its block. A block of the core library can run after its method
  # returned (an `each` that keeps the block calls it later). Then its
  # matches still set `$~` of that scope, through the Array this returns.
  # A block on another stack (a Fiber's or a Thread's) uses the record of
  # the frame that made it, while that frame lives.
  #: () -> value
  def zr_backref_scope_m
    home = zr_backref_home()
    while home != 0 && zr_block_frame_p(home) && Frame[home].entry != 0
      p = Machine.value(Frame[home].entry)
      maker = RProc[p].home
      if maker == 0 || !zr_frame_live_near(maker, RProc[p].serial)
        break
      end
      home = zr_backref_home_from(maker)
    end
    home == 0 ? Machine.value(QNIL) : zr_svars(home)
  end

  # A match that a core block made sets the `$~` of the scope that
  # zr_backref_scope_m gave, as well as its own.
  #: (value) -> value
  def zr_backref_forward_m(svars)
    if svars != QNIL
      zr_ary_store(svars, 0, zr_backref_get())
    end
    Machine.value(QNIL)
  end

  # Whether the frame `rec` with `serial` is on a stack that waits for
  # this one: this task's, the stack of each fiber that resumed this
  # fiber, or the main task's. Their records stay mapped while they wait.
  #: (ptr, word) -> bool
  def zr_frame_live_near(rec, serial)
    if zr_frame_live(rec, serial)
      return true
    end
    fiber = RFiber[zr_fiber_current()].prev
    while !zr_special_p(fiber)
      if zr_frame_on_stack(Task[RFiber[fiber].task].top, rec, serial)
        return true
      end
      fiber = RFiber[fiber].prev
    end
    zr_frame_on_stack(Task[Machine.static(:task, Task.size)].top, rec, serial)
  end

  #: (ptr, ptr, word) -> bool
  def zr_frame_on_stack(top, rec, serial)
    while top != 0
      if top == rec
        return Frame[top].serial == serial
      end
      top = Frame[top].prev
    end
    false
  end

  # The `$~` and `$_` of the frame, in an Array that is made at the first
  # write of one of them.
  #: (ptr) -> value
  def zr_svars(home)
    cell = Frame[home].svars
    if cell == QNIL
      cell = zr_ary_new(2)
      zr_ary_push(cell, Machine.value(QNIL))
      zr_ary_push(cell, Machine.value(QNIL))
      Frame[home].svars = cell
    end
    cell
  end

  #: (ptr, word) -> value
  def zr_svar_get(home, i)
    cell = Frame[home].svars
    cell == QNIL ? Machine.value(QNIL) : zr_ary_at(cell, i)
  end

  #: (value) -> value
  def zr_backref_set(v)
    home = zr_backref_home()
    if home != 0
      zr_ary_store(zr_svars(home), 0, v)
    end
    v
  end

  # `$~ = v` from a program: `v` must be a MatchData or nil, as the hook
  # of Kernel checks.
  #: (value) -> value
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

  #: () -> value
  def zr_backref_get
    home = zr_backref_home()
    home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 0)
  end

  # The hidden ivar `id` of a MatchData. `MatchData#matched` sets its
  # fields in order, so the ivar is at `row` of the table unless a copy
  # or a subclass put it elsewhere. Then it is found by name.
  #: (value, word, word) -> value
  def zr_match_field(m, id, row)
    if !zr_special_p(m) && (RBasic[m].flags & T_MASK) == T_OBJECT
      t = Machine.ptr(RObject[m].iv)
      if t != 0 && row < IvTab[t].len
        e = IvTab[t].rows + (row * IvEntry.size)
        if IvEntry[e].id == id && IvEntry[e].value != QUNDEF
          return IvEntry[e].value
        end
      end
    end
    zr_ivar_get(m, id)
  end

  inline :zr_match_field

  #: (value) -> value
  def zr_match_string(m)
    zr_match_field(m, Machine.id(:string), 1)
  end

  inline :zr_match_string

  #: (value) -> value
  def zr_match_offsets(m)
    zr_match_field(m, Machine.id(:offsets), 2)
  end

  inline :zr_match_offsets

  # The registers of a match, read as CRuby's rb_reg_nth_match and
  # related functions read them. `$1`, `$&`, `` $` ``, `$'`, `$+` and the
  # `` of a replacement never call MatchData methods that a user defines.
  # `m` is a MatchData or nil. Its offsets are
  # `[position, begin0, end0, begin1, end1, ...]`, as the search made them
  # (lib/zr/runtime/core/regexp.rb, MatchData#matched).
  #: (value, value) -> value
  def zr_match_nth(m, n)
    if m == QNIL
      return Machine.value(QNIL)
    end
    offsets = zr_match_offsets(m)
    i = zr_fix2long(n) * 2 + 1
    if i < 1 || i >= RArray[offsets].len
      return Machine.value(QNIL)
    end
    b = zr_fix2long(zr_ary_at(offsets, i))
    if b < 0
      return Machine.value(QNIL)
    end
    zr_str_byteslice(zr_match_string(m), zr_fix(b), zr_fix(zr_fix2long(zr_ary_at(offsets, i + 1)) - b))
  end

  # `$+`: the last group that matched, or nil when no group matched.
  #: (value) -> value
  def zr_match_last(m)
    if m == QNIL
      return Machine.value(QNIL)
    end
    offsets = zr_match_offsets(m)
    i = (RArray[offsets].len - 1) / 2 - 1
    while i > 0 && zr_fix2long(zr_ary_at(offsets, i * 2 + 1)) < 0
      i -= 1
    end
    if i == 0
      return Machine.value(QNIL)
    end
    zr_match_nth(m, zr_fix(i))
  end

  # `` $` ``: the text before the match.
  #: (value) -> value
  def zr_match_pre(m)
    if m == QNIL
      return Machine.value(QNIL)
    end
    zr_str_byteslice(zr_match_string(m), zr_fix(0), zr_ary_at(zr_match_offsets(m), 1))
  end

  # `$'`: the text after the match.
  #: (value) -> value
  def zr_match_post(m)
    if m == QNIL
      return Machine.value(QNIL)
    end
    s = zr_match_string(m)
    e = zr_fix2long(zr_ary_at(zr_match_offsets(m), 2))
    zr_str_byteslice(s, zr_fix(e), zr_fix(RString[s].len - e))
  end

  # `$_`, the last line read, is next to `$~`.
  #: (value) -> value
  def zr_lastline_set(v)
    home = zr_backref_home()
    if home != 0
      zr_ary_store(zr_svars(home), 1, v)
    end
    v
  end

  #: () -> value
  def zr_lastline_get
    home = zr_backref_home()
    home == 0 ? Machine.value(QNIL) : zr_svar_get(home, 1)
  end
end
