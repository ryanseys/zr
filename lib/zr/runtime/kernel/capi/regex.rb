module Zr::Kern
  # Onigmo's regex API, for C that matches a Regexp itself (strscan). A
  # regex_t is a Regexp cell: RREGEXP_PTR reads the cell's own address
  # (regexp.rb). An OnigRegion is the offsets of a match in CRuby's
  # layout, which C reads inline. The kernel's Onigmo does the matching
  # (onig_search.rb).

  # struct re_registers: `num_regs` groups, whose offsets are in `beg`
  # and `ends`, two malloc'd arrays of `allocated` words each. Ruby builds
  # Onigmo without USE_CAPTURE_HISTORY, so the struct ends there: C's own
  # regions on its stack are 24 bytes.
  class OnigRegion < Layout
    attr_accessor :allocated #: i32
    attr_accessor :num_regs #: i32
    attr_accessor :beg #: ptr
    attr_accessor :ends #: ptr
  end

  # Onigmo makes room for at least this many groups.
  ONIG_NREGION = 4
  ONIGERR_INVALID_ARGUMENT = 0 - 30
  ONIGERR_UNDEFINED_NAME_REFERENCE = 0 - 217

  # onig_region_init: an empty region.
  #: (ptr) -> void
  def onig_region_init(region)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_init(region)
  end

  #: (ptr) -> void
  def zr_capi_region_init(region)
    Libc.memset(region, Machine.i32(0), OnigRegion.size)
  end

  # onig_region_new: an empty region of its own, for
  # onig_region_free(region, 1).
  #: () -> ptr
  def onig_region_new
    Machine.gates_enter
    zr_c_entered()
    region = zr_xmalloc(OnigRegion.size)
    zr_capi_region_init(region)
    region
  end

  # onig_region_resize: room for `n` groups, and `n` in use.
  #: (ptr, i32) -> i32
  def onig_region_resize(region, n)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_resize(region, Machine.sword(n))
    Machine.i32(0)
  end

  #: (ptr, word) -> void
  def zr_capi_region_resize(region, n)
    OnigRegion[region].num_regs = Machine.i32(n)
    room = n < ONIG_NREGION ? ONIG_NREGION : n
    zr_capi_region_reserve(region, room)
  end

  # Room for `room` groups at least.
  #: (ptr, word) -> void
  def zr_capi_region_reserve(region, room)
    have = Machine.sword(OnigRegion[region].allocated)
    if have == 0
      OnigRegion[region].beg = zr_xmalloc(room * 8)
      OnigRegion[region].ends = zr_xmalloc(room * 8)
      OnigRegion[region].allocated = Machine.i32(room)
    elsif have < room
      OnigRegion[region].beg = zr_capi_realloc(OnigRegion[region].beg, room * 8)
      OnigRegion[region].ends = zr_capi_realloc(OnigRegion[region].ends, room * 8)
      OnigRegion[region].allocated = Machine.i32(room)
    end
  end

  # onig_region_clear: each group in use matched nothing.
  #: (ptr) -> void
  def onig_region_clear(region)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_clear(region)
  end

  #: (ptr) -> void
  def zr_capi_region_clear(region)
    i = 0
    while i < Machine.sword(OnigRegion[region].num_regs)
      zr_capi_region_put(region, i, ONIG_REGION_NOTPOS, ONIG_REGION_NOTPOS)
      i += 1
    end
  end

  #: (ptr, word, word, word) -> void
  def zr_capi_region_put(region, i, beg, stop)
    Machine.store64(OnigRegion[region].beg + (i * 8), 0, beg)
    Machine.store64(OnigRegion[region].ends + (i * 8), 0, stop)
  end

  # onig_region_free: frees the offsets, and the region itself when
  # `free_self`; otherwise the region is empty again.
  #: (ptr, i32) -> void
  def onig_region_free(region, free_self)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_free(region, Machine.sword(free_self) != 0)
  end

  #: (ptr, bool) -> void
  def zr_capi_region_free(region, free_self)
    if region == 0
      return
    end
    if Machine.sword(OnigRegion[region].allocated) > 0
      zr_xfree(OnigRegion[region].beg)
      zr_xfree(OnigRegion[region].ends)
    end
    if free_self
      zr_xfree(region)
    else
      zr_capi_region_init(region)
    end
  end

  # onig_region_set: group `at` is beg...stop; the region grows to hold it.
  #: (ptr, i32, i32, i32) -> i32
  def onig_region_set(region, at, beg, stop)
    Machine.gates_enter
    zr_c_entered()
    i = Machine.sword(at)
    if i < 0
      return Machine.i32(ONIGERR_INVALID_ARGUMENT)
    end
    if i >= Machine.sword(OnigRegion[region].allocated)
      zr_capi_region_resize(region, i + 1)
    end
    zr_capi_region_put(region, i, Machine.sword(beg), Machine.sword(stop))
    Machine.i32(0)
  end

  # onig_region_copy and rb_reg_region_copy: `to` holds the groups of
  # `from`. rb_reg_region_copy gives 0, as it has room.
  #: (ptr, ptr) -> void
  def onig_region_copy(to, from)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_copy(to, from)
  end

  #: (ptr, ptr) -> i32
  def rb_reg_region_copy(to, from)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_region_copy(to, from)
    Machine.i32(0)
  end

  #: (ptr, ptr) -> void
  def zr_capi_region_copy(to, from)
    if to == from
      return
    end
    n = Machine.sword(OnigRegion[from].num_regs)
    zr_capi_region_resize(to, n)
    zr_memcpy(OnigRegion[to].beg, OnigRegion[from].beg, n * 8)
    zr_memcpy(OnigRegion[to].ends, OnigRegion[from].ends, n * 8)
  end

  # onig_region_memsize: the bytes of the region and its offsets.
  #: (ptr) -> word
  def onig_region_memsize(region)
    Machine.gates_enter
    zr_c_entered()
    OnigRegion.size + (Machine.sword(OnigRegion[region].allocated) * 16)
  end

  # onig_search: where `reg` first matches str...text_end, searching from
  # `start` toward `range`, or ONIG_MISMATCH. The groups go into
  # `region` (if not NULL), as offsets from `str`.
  #: (word, ptr, ptr, ptr, ptr, ptr, i32) -> word
  def onig_search(reg, str, text_end, start, range, region, option)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_regex_run(Machine.value(reg), str, text_end, start, range, region, true)
  end

  # onig_match: the length of the match of `reg` at exactly `at`, or
  # ONIG_MISMATCH.
  #: (word, ptr, ptr, ptr, ptr, i32) -> word
  def onig_match(reg, str, text_end, at, region, option)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_regex_run(Machine.value(reg), str, text_end, at, text_end, region, false)
  end

  # Runs the program of the Regexp `re` over the bytes str...text_end, as
  # onig_search (`search`) or onig_match does.
  #: (value, ptr, ptr, ptr, ptr, ptr, bool) -> word
  def zr_capi_regex_run(re, str, text_end, start, range, region, search)
    if RRegexp[re].program == QNIL
      # Regexp.allocate's cell: `pattern` raises CRuby's TypeError.
      zr_c_result(zr_send(re, Machine.id(:pattern), 0, Machine.ptr(0)))
    end
    prog = RString[RRegexp[re].program].ptr
    groups = OnigProg[prog].num_mem + 1
    found = zr_regexp_region_new(prog)
    r = 0
    if search
      r = zr_onig_search(prog, str, text_end, start, range, found, zr_regexp_limit_for(re))
    else
      r = zr_onig_match(prog, str, text_end, start, found, zr_regexp_limit_for(re))
    end
    if region != 0
      zr_capi_region_resize(region, groups)
      if r >= 0
        i = 0
        while i < groups
          zr_capi_region_put(region, i, Machine.load64(found + (i * 16), 0), Machine.load64(found + (i * 16), 8))
          i += 1
        end
      else
        zr_capi_region_clear(region)
      end
    end
    zr_regexp_region_free(found)
    r
  end

  # rb_reg_onig_match: calls `match(reg, str, regs, args)` with the
  # regex_t of `re` for `str`'s encoding, as strscan matches. A match
  # error other than no match raises; a timeout raises
  # Regexp::TimeoutError.
  #: (value, value, ptr, word, ptr) -> word
  def rb_reg_onig_match(re, str, match, args, regs)
    Machine.gates_enter
    zr_c_entered()
    reg = zr_capi_reg_prepare(re, str)
    own = Machine.slot(OnigRegion.size)
    region = regs
    if region == 0
      zr_capi_region_init(own)
      region = own
    end
    argv = Machine.slot(64)
    Machine.store64(argv, 0, Machine.word(reg))
    Machine.store64(argv, 8, Machine.word(str))
    Machine.store64(argv, 16, Machine.word(region))
    Machine.store64(argv, 24, args)
    RRegexp[reg].usecnt = RRegexp[reg].usecnt + 1
    returned = zr_call_c_returned(match, argv, 4)
    RRegexp[reg].usecnt = RRegexp[reg].usecnt - 1
    if regs == 0
      zr_capi_region_free(own, false)
    end
    if !returned
      zr_c_unwind()
    end
    r = Machine.load64(argv, 0)
    if r < 0 && r != ONIG_MISMATCH
      zr_c_result(zr_capi_regex_failed(r))
    end
    r
  end

  # rb_reg_prepare_re: `re` itself, or, for a `str` in an encoding that
  # needs the pattern compiled again, a new Regexp with that program.
  #: (value, value) -> value
  def zr_capi_reg_prepare(re, str)
    program = zr_capi_call1(re, Machine.id(:program_for), str)
    if program == QNIL
      return re
    end
    prepared = zr_regexp_alloc(zr_core_class(Machine.id(:Regexp)))
    zr_regexp_copy_from(prepared, re)
    RRegexp[prepared].program = program
    prepared
  end

  # The error of a match that failed with the Onigmo code `r`.
  #: (word) -> value
  def zr_capi_regex_failed(r)
    if r == ONIGERR_TIMEOUT
      return zr_regexp_failed(r)
    end
    zr_raise_msg(zr_core_class(Machine.id(:RegexpError)), Machine.bytes("regexp match failed"), 19)
  end

  # onig_name_to_backref_number: the group of the name name...name_end:
  # of a name that more groups share, the last one that matched in
  # `region` (if not NULL), else the last one.
  #: (word, ptr, ptr, ptr) -> i32
  def onig_name_to_backref_number(reg, name, name_end, region)
    Machine.gates_enter
    zr_c_entered()
    rows = zr_capi_regex_names(Machine.value(reg))
    len = Machine.word(name_end) - Machine.word(name)
    i = 0
    while i < RArray[rows].len
      row = zr_ary_at(rows, i)
      s = zr_ary_at(row, 0)
      if zr_bytes_eq(RString[s].ptr, RString[s].len, name, len)
        return Machine.i32(zr_capi_backref(zr_ary_at(row, 1), region))
      end
      i += 1
    end
    Machine.i32(ONIGERR_UNDEFINED_NAME_REFERENCE)
  end

  # The group of `groups` (an Array of numbers) that a backreference by
  # name means.
  #: (value, ptr) -> word
  def zr_capi_backref(groups, region)
    n = RArray[groups].len
    if region != 0
      i = n - 1
      while i >= 0
        g = zr_fix2long(zr_ary_at(groups, i))
        if g < Machine.sword(OnigRegion[region].num_regs) && Machine.load64(OnigRegion[region].beg + (g * 8), 0) != ONIG_REGION_NOTPOS
          return g
        end
        i -= 1
      end
    end
    zr_fix2long(zr_ary_at(groups, n - 1))
  end

  # onig_foreach_name: calls `func(name, name_end, ngroups, groups, reg,
  # arg)` for each name in the order the pattern defines them, until one
  # call gives nonzero, which it returns.
  #: (word, ptr, word) -> i32
  def onig_foreach_name(reg, func, arg)
    Machine.gates_enter
    zr_c_entered()
    rows = zr_capi_regex_names(Machine.value(reg))
    argv = Machine.slot(64)
    i = 0
    while i < RArray[rows].len
      row = zr_ary_at(rows, i)
      name = zr_ary_at(row, 0)
      groups = zr_ary_at(row, 1)
      n = RArray[groups].len
      list = zr_xmalloc(n * 4)
      j = 0
      while j < n
        Machine.store32(list + (j * 4), 0, Machine.i32(zr_fix2long(zr_ary_at(groups, j))))
        j += 1
      end
      Machine.store64(argv, 0, Machine.word(RString[name].ptr))
      Machine.store64(argv, 8, Machine.word(RString[name].ptr + RString[name].len))
      Machine.store64(argv, 16, n)
      Machine.store64(argv, 24, Machine.word(list))
      Machine.store64(argv, 32, reg)
      Machine.store64(argv, 40, arg)
      returned = zr_call_c_returned(func, argv, 6)
      zr_xfree(list)
      if !returned
        zr_c_unwind()
      end
      r = Machine.sword(Machine.i32(Machine.load64(argv, 0)))
      if r != 0
        return Machine.i32(r)
      end
      i += 1
    end
    Machine.i32(0)
  end

  # The named groups of `re` in definition order: [[name, [groups]], ...].
  #: (value) -> value
  def zr_capi_regex_names(re)
    zr_c_result(zr_send(re, Machine.id(:name_rows), 0, Machine.ptr(0)))
  end

  # onig_new: compiles the pattern pattern...pattern_end in the encoding
  # `enc` into `*reg`, a new Regexp that stays alive until onig_free; or
  # gives the Onigmo error code of a pattern that does not compile. The
  # syntax is Ruby's, and `einfo` names no bytes.
  #: (ptr, ptr, ptr, i32, ptr, ptr, ptr) -> i32
  def onig_new(reg, pattern, pattern_end, option, enc, syntax, einfo)
    Machine.gates_enter
    zr_c_entered()
    source = zr_capi_str(pattern, Machine.word(pattern_end) - Machine.word(pattern), zr_capi_enc_index(enc))
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(source))
    Machine.store64(args, 8, Machine.word(zr_fix(Machine.u32(option))))
    re = zr_c_result(zr_send(zr_core_class(Machine.id(:Regexp)), Machine.id(:c_onig_new), 2, args))
    if einfo != 0
      Libc.memset(einfo, Machine.i32(0), 24)
    end
    if zr_fixnum_p(re)
      return Machine.i32(zr_fix2long(re))
    end
    zr_weak_list_push(zr_c_root_objects(), re)
    Machine.store64(reg, 0, Machine.word(re))
    Machine.i32(0)
  end

  # onig_free: the Regexp of onig_new may die.
  #: (word) -> void
  def onig_free(reg)
    Machine.gates_enter
    zr_c_entered()
    zr_c_root_object_drop(Machine.value(reg))
  end

  # ONIG_MAX_ERROR_MESSAGE_LEN: the room that C gives the message.
  ONIG_MAX_ERROR_MESSAGE_LEN = 90

  # onig_error_code_to_str: Onigmo's message for the error `code` in the
  # buffer `buf`, ended with a NUL; gives its length.
  #: (ptr, word) -> i32
  def onig_error_code_to_str(buf, code)
    Machine.gates_enter
    zr_c_entered()
    text = zr_capi_call1(zr_core_class(Machine.id(:Regexp)), Machine.id(:c_onig_error), zr_fix(code))
    n = RString[text].len
    if n >= ONIG_MAX_ERROR_MESSAGE_LEN
      n = ONIG_MAX_ERROR_MESSAGE_LEN - 1
    end
    zr_memcpy(buf, RString[text].ptr, n)
    Machine.store8(buf + n, 0, Machine.i8(0))
    Machine.i32(n)
  end
end
