# Derived from Onigmo (BSD-2-Clause); see THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # onig_search_gpos and onig_match (regexec.c:4238-5281): the search
  # drivers that call match_at. They include the anchor pre-checks, the
  # optimizer's exact-string and map searches, and forward_search_range /
  # backward_search_range. Derived from Onigmo; the license is in
  # lib/zr/runtime/kernel/regexp.rb.
  ONIG_OPTIMIZE_NONE = 0
  ONIG_OPTIMIZE_EXACT = 1
  ONIG_OPTIMIZE_EXACT_BM = 2
  ONIG_OPTIMIZE_EXACT_BM_NOT_REV = 3
  ONIG_OPTIMIZE_EXACT_IC = 4
  ONIG_OPTIMIZE_MAP = 5
  ONIG_OPTIMIZE_EXACT_BM_IC = 6
  ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC = 7
  ONIG_ANCHOR_BEGIN_BUF = 1
  ONIG_ANCHOR_BEGIN_LINE = 2
  ONIG_ANCHOR_BEGIN_POSITION = 4
  ONIG_ANCHOR_END_BUF = 8
  ONIG_ANCHOR_SEMI_END_BUF = 16
  ONIG_ANCHOR_END_LINE = 32
  ONIG_ANCHOR_PREC_READ_NOT = 2048
  ONIG_ANCHOR_LOOK_BEHIND = 4096
  ONIG_ANCHOR_ANYCHAR_STAR = 16384
  ONIG_ANCHOR_ANYCHAR_STAR_ML = 32768

  # The two buffers that a search needs: its region and the match state's
  # arena. They stay between searches, because a malloc and a free for
  # each match is slow: `String#scan` on a long text can make tens of
  # thousands of matches. Each buffer is one record of `ptr, capacity,
  # busy`, which grows to the largest request. If a record is busy (a
  # search inside a search), the call gets a new malloc, and the free
  # after it tells the two apart by the address.
  SCRATCH_ROW = 24

  #: (word, word) -> ptr
  def zr_onig_scratch(row, bytes)
    s = Machine.static(:onig_scratch, SCRATCH_ROW * 2) + (row * SCRATCH_ROW)
    if Machine.load64(s, 16) != 0
      p = Libc.malloc(bytes)
      Libc.abort() if p == 0
      return p
    end
    if Machine.load64(s, 8) < bytes
      if Machine.load64(s, 0) != 0
        Libc.free(Machine.ptr(Machine.load64(s, 0)))
      end
      p = Libc.malloc(bytes)
      Libc.abort() if p == 0
      Machine.store64(s, 0, Machine.word(p))
      Machine.store64(s, 8, bytes)
    end
    Machine.store64(s, 16, 1)
    Machine.ptr(Machine.load64(s, 0))
  end

  #: (word, ptr) -> void
  def zr_onig_scratch_free(row, p)
    s = Machine.static(:onig_scratch, SCRATCH_ROW * 2) + (row * SCRATCH_ROW)
    if Machine.word(p) == Machine.load64(s, 0)
      Machine.store64(s, 16, 0)
    else
      Libc.free(p)
    end
  end

  # Makes the match state for a search of `prog` in str..text_end. It
  # writes `region` (a word array of 2 * (num_mem + 1), or 0), with a time
  # `limit` in nanoseconds (0 for no limit). This is MATCH_ARG_INIT plus
  # the arena of STACK_INIT: the index words and the first stack, in one
  # malloc.
  #: (ptr, ptr, ptr, ptr, ptr, word) -> void
  def zr_onig_msa_init(m, prog, str, text_end, region, limit)
    OnigMatch[m].prog = prog
    OnigMatch[m].code = prog + OnigProg[prog].code_off
    OnigMatch[m].enc = zr_onig_prog_enc(prog)
    OnigMatch[m].options = OnigProg[prog].options
    OnigMatch[m].case_fold = OnigProg[prog].case_fold_flag
    num_mem = OnigProg[prog].num_mem
    OnigMatch[m].num_mem = num_mem
    OnigMatch[m].pop_level = OnigProg[prog].pop_level
    OnigMatch[m].bt_mem_start = OnigProg[prog].bt_mem_start
    OnigMatch[m].bt_mem_end = OnigProg[prog].bt_mem_end
    OnigMatch[m].str = str
    OnigMatch[m].text_end = text_end
    OnigMatch[m].region = region
    OnigMatch[m].mopts = 0
    OnigMatch[m].stack_p = Machine.ptr(0)
    OnigMatch[m].stack_n = 0
    OnigMatch[m].counter = 0
    OnigMatch[m].end_time = 0
    OnigMatch[m].limit = limit
    OnigMatch[m].best_len = ONIG_MISMATCH
    # MATCH_ARG_INIT_MATCH_CACHE
    OnigMatch[m].match_cache_status = ONIG_MATCH_CACHE_STATUS_UNINIT
    OnigMatch[m].num_fails = 0
    OnigMatch[m].num_cache_opcodes = ONIG_NUM_CACHE_OPCODES_UNINIT
    OnigMatch[m].cache_opcodes = Machine.ptr(0)
    OnigMatch[m].num_cache_points = 0
    OnigMatch[m].match_cache_buf = Machine.ptr(0)
    num_repeat = OnigProg[prog].num_repeat
    # ADD_NUMMEM: group 0 also has a slot, for \g<0>.
    words = num_repeat + ((num_mem + 1) * 2)
    arena = zr_onig_scratch(1, (words * 8) + (ONIG_INIT_MATCH_STACK_SIZE * OnigStk.size))
    OnigMatch[m].repeat_stk = arena
    OnigMatch[m].mem_start_stk = arena + (num_repeat * 8)
    OnigMatch[m].mem_end_stk = arena + (num_repeat * 8) + ((num_mem + 1) * 8)
    OnigMatch[m].stk_alloc = arena + (words * 8)
  end

  # MATCH_ARG_FREE (with the match cache's entries and bits) and the
  # arena.
  #: (ptr) -> void
  def zr_onig_msa_free(m)
    if OnigMatch[m].stack_p != 0
      Libc.free(OnigMatch[m].stack_p)
    end
    if OnigMatch[m].cache_opcodes != 0
      Libc.free(OnigMatch[m].cache_opcodes)
    end
    if OnigMatch[m].match_cache_buf != 0
      Libc.free(OnigMatch[m].match_cache_buf)
    end
    zr_onig_scratch_free(1, OnigMatch[m].repeat_stk)
  end

  # onig_region_resize_clear: sets every position to ONIG_REGION_NOTPOS.
  #: (ptr, word) -> void
  def zr_onig_region_clear(region, num_mem)
    i = 0
    while i <= num_mem
      Machine.store64(region + (i * 16), 0, ONIG_REGION_NOTPOS)
      Machine.store64(region + (i * 16), 8, ONIG_REGION_NOTPOS)
      i += 1
    end
  end

  # The optimizer's exact bytes and their end.
  #: (ptr) -> ptr
  def zr_onig_exact(prog)
    prog + OnigProg[prog].exact_off
  end

  #: (ptr) -> ptr
  def zr_onig_exact_end(prog)
    prog + OnigProg[prog].exact_off + OnigProg[prog].exact_len
  end

  #: (ptr, word) -> word
  def zr_onig_map_at(prog, c)
    Machine.u8(Machine.load8(prog + OnigProg[prog].map_off + c, 0))
  end

  # slow_search.
  #: (word, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_slow_search(enc, target, target_end, text, text_end, text_range)
    e = text_end - (target_end - target - 1)
    if e > text_range
      e = text_range
    end
    s = text
    while s < e
      if Machine.load8(s, 0) == Machine.load8(target, 0)
        p = s + 1
        t = target + 1
        matched = true
        while t < target_end
          if Machine.load8(t, 0) != Machine.load8(p, 0)
            matched = false
            break
          end
          t = t + 1
          p = p + 1
        end
        return s if matched
      end
      s = s + zr_onig_enclen(enc, s, text_end)
    end
    Machine.ptr(0)
  end

  # slow_search_ic.
  #: (word, word, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_slow_search_ic(enc, flag, target, target_end, text, text_end, text_range)
    e = text_end - (target_end - target - 1)
    if e > text_range
      e = text_range
    end
    s = text
    while s < e
      return s if zr_onig_str_lower_case_match(enc, flag, target, target_end, s, text_end)
      s = s + zr_onig_enclen(enc, s, text_end)
    end
    Machine.ptr(0)
  end

  # slow_search_backward.
  #: (word, ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_slow_search_backward(enc, target, target_end, text, adjust_text, text_end, text_start)
    s = text_end - (target_end - target)
    if s > text_start
      s = text_start
    else
      s = zr_onig_left_adjust(enc, adjust_text, s, text_end)
    end
    while s >= text
      if Machine.load8(s, 0) == Machine.load8(target, 0)
        p = s + 1
        t = target + 1
        while t < target_end
          break if Machine.load8(t, 0) != Machine.load8(p, 0)
          p = p + 1
          t = t + 1
        end
        return s if t == target_end
      end
      s = zr_onig_prev_char_head(enc, adjust_text, s, text_end)
      break if s == 0
    end
    Machine.ptr(0)
  end

  # slow_search_backward_ic.
  #: (word, word, ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_slow_search_backward_ic(enc, flag, target, target_end, text, adjust_text, text_end, text_start)
    s = text_end - (target_end - target)
    if s > text_start
      s = text_start
    else
      s = zr_onig_left_adjust(enc, adjust_text, s, text_end)
    end
    while s >= text
      return s if zr_onig_str_lower_case_match(enc, flag, target, target_end, s, text_end)
      s = zr_onig_prev_char_head(enc, adjust_text, s, text_end)
      break if s == 0
    end
    Machine.ptr(0)
  end

  # bm_search_notrev: Sunday's quick search for a multibyte string.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_bm_search_notrev(prog, target, target_end, text, text_end, text_range)
    enc = zr_onig_prog_enc(prog)
    tail = target_end - 1
    tlen1 = Machine.word(tail - target)
    e = text_range
    if e + tlen1 > text_end
      e = text_end - tlen1
    end
    s = text
    while s < e
      se = s + tlen1
      p = se
      t = tail
      while Machine.load8(p, 0) == Machine.load8(t, 0)
        return s if t == target
        p = p - 1
        t = t - 1
      end
      break if s + 1 >= e
      skip = zr_onig_map_at(prog, Machine.u8(Machine.load8(se, 1)))
      t = s
      while true
        s = s + zr_onig_enclen(enc, s, e)
        break if !(Machine.word(s - t) < skip && s < e)
      end
    end
    Machine.ptr(0)
  end

  # bm_search: Sunday's quick search.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_bm_search(prog, target, target_end, text, text_end, text_range)
    tail = target_end - 1
    tlen1 = Machine.word(tail - target)
    e = text_range + tlen1
    if e > text_end
      e = text_end
    end
    s = text + tlen1
    while s < e
      p = s
      t = tail
      while Machine.load8(p, 0) == Machine.load8(t, 0)
        return p if t == target
        p = p - 1
        t = t - 1
      end
      break if s + 1 >= e
      s = s + zr_onig_map_at(prog, Machine.u8(Machine.load8(s, 1)))
    end
    Machine.ptr(0)
  end

  # bm_search_notrev_ic.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_bm_search_notrev_ic(prog, target, target_end, text, text_end, text_range)
    enc = zr_onig_prog_enc(prog)
    tail = target_end - 1
    tlen1 = Machine.word(tail - target)
    e = text_range
    if e + tlen1 > text_end
      e = text_end - tlen1
    end
    s = text
    while s < e
      se = s + tlen1
      return s if zr_onig_str_lower_case_match(enc, OnigProg[prog].case_fold_flag, target, target_end, s, se + 1)
      break if s + 1 >= e
      skip = zr_onig_map_at(prog, Machine.u8(Machine.load8(se, 1)))
      t = s
      while true
        s = s + zr_onig_enclen(enc, s, e)
        break if !(Machine.word(s - t) < skip && s < e)
      end
    end
    Machine.ptr(0)
  end

  # bm_search_ic.
  #: (ptr, ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_bm_search_ic(prog, target, target_end, text, text_end, text_range)
    enc = zr_onig_prog_enc(prog)
    tail = target_end - 1
    tlen1 = Machine.word(tail - target)
    e = text_range + tlen1
    if e > text_end
      e = text_end
    end
    s = text + tlen1
    while s < e
      p = s - tlen1
      return p if zr_onig_str_lower_case_match(enc, OnigProg[prog].case_fold_flag, target, target_end, p, s + 1)
      break if s + 1 >= e
      s = s + zr_onig_map_at(prog, Machine.u8(Machine.load8(s, 1)))
    end
    Machine.ptr(0)
  end

  # map_search.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_map_search(prog, text, text_range, text_end)
    enc = zr_onig_prog_enc(prog)
    s = text
    while s < text_range
      return s if zr_onig_map_at(prog, Machine.u8(Machine.load8(s, 0))) != 0
      s = s + zr_onig_enclen(enc, s, text_end)
    end
    Machine.ptr(0)
  end

  # map_search_backward.
  #: (ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_map_search_backward(prog, text, adjust_text, text_start, text_end)
    enc = zr_onig_prog_enc(prog)
    s = text_start
    while s >= text
      return s if zr_onig_map_at(prog, Machine.u8(Machine.load8(s, 0))) != 0
      s = zr_onig_prev_char_head(enc, adjust_text, s, text_end)
      break if s == 0
    end
    Machine.ptr(0)
  end

  # The optimizer's forward search from p, as reg->optimize selects.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_forward_find(prog, p, text_end, range)
    optimize = OnigProg[prog].optimize
    enc = zr_onig_prog_enc(prog)
    exact = zr_onig_exact(prog)
    exact_end = zr_onig_exact_end(prog)
    return zr_onig_slow_search(enc, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT
    return zr_onig_slow_search_ic(enc, OnigProg[prog].case_fold_flag, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_IC
    return zr_onig_bm_search(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM
    return zr_onig_bm_search_notrev(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV
    return zr_onig_bm_search_ic(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_IC
    return zr_onig_bm_search_notrev_ic(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC
    return zr_onig_map_search(prog, p, range, text_end) if optimize == ONIG_OPTIMIZE_MAP
    Machine.ptr(0)
  end

  # forward_search_range: whether the optimizer finds a possible match
  # start from s before range. It writes the match window to the words
  # `low`, `high` and (when not 0) `low_prev`.
  #: (ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr) -> bool
  def zr_onig_forward_search_range(prog, str, text_end, s, range, low, high, low_prev)
    enc = zr_onig_prog_enc(prog)
    dmin = OnigProg[prog].dmin
    dmax = OnigProg[prog].dmax
    pprev = Machine.ptr(0)
    return false if dmin > Machine.word(text_end - str)
    p = s
    if dmin != 0
      return false if Machine.word(text_end - p) <= dmin
      if zr_onig_enc_single_byte_p(enc)
        p = p + dmin
      else
        q = p + dmin
        while p < q
          p = p + zr_onig_enclen(enc, p, text_end)
        end
      end
    end
    while true
      p = zr_onig_forward_find(prog, p, text_end, range)
      return false if p == 0 || p >= range
      again = false
      if Machine.word(p - s) < dmin
        again = true
      elsif OnigProg[prog].sub_anchor == ONIG_ANCHOR_BEGIN_LINE
        if p != str
          prev = zr_onig_prev_char_head(enc, pprev != 0 ? pprev : str, p, text_end)
          again = true if !zr_onig_newline_p(enc, prev, text_end)
        end
      elsif OnigProg[prog].sub_anchor == ONIG_ANCHOR_END_LINE
        # The empty line at the end of the text counts as a line
        # (USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE).
        if p != text_end && !zr_onig_newline_p(enc, p, text_end)
          again = true
        end
      end
      if again
        pprev = p
        p = p + zr_onig_enclen(enc, p, text_end)
      else
        break
      end
    end
    if dmax == 0
      Machine.store64(low, 0, Machine.word(p))
      if low_prev != 0
        if p > s
          Machine.store64(low_prev, 0, Machine.word(zr_onig_prev_char_head(enc, s, p, text_end)))
        else
          Machine.store64(low_prev, 0, Machine.word(zr_onig_prev_char_head(enc, pprev != 0 ? pprev : str, p, text_end)))
        end
      end
      Machine.store64(high, 0, Machine.word(p))
    else
      if dmax != ONIG_INFINITE_DISTANCE
        if Machine.word(p - str) < dmax
          Machine.store64(low, 0, Machine.word(str))
          if low_prev != 0
            Machine.store64(low_prev, 0, Machine.word(zr_onig_prev_char_head(enc, str, str, text_end)))
          end
        else
          lo = p - dmax
          if lo > s
            # onigenc_get_right_adjust_char_head_with_prev
            adj = zr_onig_left_adjust(enc, s, lo, text_end)
            if adj < lo
              if low_prev != 0
                Machine.store64(low_prev, 0, Machine.word(adj))
              end
              adj = adj + zr_onig_enclen(enc, adj, text_end)
            else
              if low_prev != 0
                Machine.store64(low_prev, 0, Machine.word(zr_onig_prev_char_head(enc, pprev != 0 ? pprev : s, adj, text_end)))
              end
            end
            lo = adj
          else
            if low_prev != 0
              Machine.store64(low_prev, 0, Machine.word(zr_onig_prev_char_head(enc, pprev != 0 ? pprev : str, lo, text_end)))
            end
          end
          Machine.store64(low, 0, Machine.word(lo))
        end
      end
      # *high needs no adjustment, because it is used only as a range check.
      if Machine.word(p - str) < dmin
        Machine.store64(high, 0, Machine.word(str))
      else
        Machine.store64(high, 0, Machine.word(p - dmin))
      end
    end
    true
  end

  # The optimizer's backward search from p, as reg->optimize selects.
  #: (ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_onig_backward_find(prog, p, range, adjrange, text_end)
    optimize = OnigProg[prog].optimize
    enc = zr_onig_prog_enc(prog)
    exact = zr_onig_exact(prog)
    exact_end = zr_onig_exact_end(prog)
    if optimize == ONIG_OPTIMIZE_EXACT || optimize == ONIG_OPTIMIZE_EXACT_BM || optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV
      return zr_onig_slow_search_backward(enc, exact, exact_end, range, adjrange, text_end, p)
    end
    if optimize == ONIG_OPTIMIZE_EXACT_IC || optimize == ONIG_OPTIMIZE_EXACT_BM_IC || optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC
      return zr_onig_slow_search_backward_ic(enc, OnigProg[prog].case_fold_flag, exact, exact_end, range, adjrange, text_end, p)
    end
    return zr_onig_map_search_backward(prog, range, adjrange, p, text_end) if optimize == ONIG_OPTIMIZE_MAP
    Machine.ptr(0)
  end

  # backward_search_range.
  #: (ptr, ptr, ptr, ptr, ptr, ptr, ptr, ptr) -> bool
  def zr_onig_backward_search_range(prog, str, text_end, s, range, adjrange, low, high)
    enc = zr_onig_prog_enc(prog)
    dmin = OnigProg[prog].dmin
    dmax = OnigProg[prog].dmax
    return false if dmin > Machine.word(text_end - str)
    p = s
    while true
      p = zr_onig_backward_find(prog, p, range, adjrange, text_end)
      return false if p == 0
      again = false
      if OnigProg[prog].sub_anchor == ONIG_ANCHOR_BEGIN_LINE
        if p != str
          prev = zr_onig_prev_char_head(enc, str, p, text_end)
          if !zr_onig_newline_p(enc, prev, text_end)
            p = prev
            again = true
          end
        end
      elsif OnigProg[prog].sub_anchor == ONIG_ANCHOR_END_LINE
        if p != text_end && !zr_onig_newline_p(enc, p, text_end)
          p = zr_onig_prev_char_head(enc, adjrange, p, text_end)
          return false if p == 0
          again = true
        end
      end
      break if !again
    end
    if dmax != ONIG_INFINITE_DISTANCE
      if Machine.word(p - str) < dmax
        Machine.store64(low, 0, Machine.word(str))
      else
        Machine.store64(low, 0, Machine.word(p - dmax))
      end
      if dmin != 0
        if Machine.word(p - str) < dmin
          Machine.store64(high, 0, Machine.word(str))
        else
          Machine.store64(high, 0, Machine.word(p - dmin))
        end
      else
        Machine.store64(high, 0, Machine.word(p))
      end
      Machine.store64(high, 0, Machine.word(zr_onig_right_adjust(enc, adjrange, Machine.ptr(Machine.load64(high, 0)), text_end)))
    end
    true
  end

  # MATCH_AND_RETURN_CHECK: runs match_at at s. Returns the match's
  # position, ONIG_MISMATCH to continue, or an error to stop.
  #: (ptr, ptr, ptr) -> word
  def zr_onig_try_at(m, s, prev)
    r = zr_onig_match_at(m, s, prev)
    return Machine.word(s - OnigMatch[m].str) if r >= 0
    r
  end

  # onig_search_gpos with the match state `m` (from zr_onig_msa_init), and
  # global_pos for \G. Returns the match position, ONIG_MISMATCH, or an
  # error code.
  #: (ptr, ptr, ptr, ptr) -> word
  def zr_onig_search_gpos(m, global_pos, start, range)
    prog = OnigMatch[m].prog
    str = OnigMatch[m].str
    text_end = OnigMatch[m].text_end
    enc = zr_onig_prog_enc(prog)
    region = OnigMatch[m].region
    if region != 0
      zr_onig_region_clear(region, OnigProg[prog].num_mem)
    end
    return ONIG_MISMATCH if start > text_end || start < str
    anchor = OnigProg[prog].anchor
    # Anchor optimization: narrow the search range.
    if anchor != 0 && str < text_end
      anchor_dmin = OnigProg[prog].anchor_dmin
      anchor_dmax = OnigProg[prog].anchor_dmax
      end_buf = false
      min_semi_end = text_end
      max_semi_end = text_end
      if (anchor & ONIG_ANCHOR_BEGIN_POSITION) != 0 || (anchor & ONIG_ANCHOR_ANYCHAR_STAR_ML) != 0 && (anchor & (ONIG_ANCHOR_BEGIN_BUF | ONIG_ANCHOR_END_BUF | ONIG_ANCHOR_SEMI_END_BUF)) == 0
        # Search only at the start position.
        if range > start
          if global_pos > start
            if global_pos < range
              range = global_pos + 1
            end
          else
            range = start + 1
          end
        else
          range = start
        end
      elsif (anchor & ONIG_ANCHOR_BEGIN_BUF) != 0
        # Search only at the str position.
        if range > start
          return ONIG_MISMATCH if start != str
          range = str + 1
        else
          if range <= str
            start = str
            range = str
          else
            return ONIG_MISMATCH
          end
        end
      elsif (anchor & ONIG_ANCHOR_END_BUF) != 0
        end_buf = true
      elsif (anchor & ONIG_ANCHOR_SEMI_END_BUF) != 0
        pre_end = zr_onig_step_back(enc, str, text_end, text_end, 1)
        if zr_onig_newline_p(enc, pre_end, text_end)
          min_semi_end = pre_end
          if min_semi_end > str && start <= min_semi_end
            end_buf = true
          end
        else
          end_buf = true
        end
      end
      if end_buf
        return ONIG_MISMATCH if Machine.word(max_semi_end - str) < anchor_dmin
        if range > start
          if Machine.word(min_semi_end - start) > anchor_dmax
            start = min_semi_end - anchor_dmax
            if start < text_end
              start = zr_onig_right_adjust(enc, str, start, text_end)
            end
          end
          if Machine.word(max_semi_end - (range - 1)) < anchor_dmin
            return ONIG_MISMATCH if Machine.word(max_semi_end - str + 1) < anchor_dmin
            range = max_semi_end - anchor_dmin + 1
          end
          return ONIG_MISMATCH if start > range
          # If start == range, match the empty string at the end. This uses
          # a backward search.
        else
          if Machine.word(min_semi_end - range) > anchor_dmax
            range = min_semi_end - anchor_dmax
          end
          if Machine.word(max_semi_end - start) < anchor_dmin
            return ONIG_MISMATCH if Machine.word(max_semi_end - str) < anchor_dmin
            start = max_semi_end - anchor_dmin
            start = zr_onig_left_adjust(enc, str, start, text_end)
          end
          return ONIG_MISMATCH if range > start
        end
      end
    elsif str == text_end
      # The empty string.
      return ONIG_MISMATCH if OnigProg[prog].threshold_len != 0
      OnigMatch[m].gpos = start
      return zr_onig_try_at(m, start, Machine.ptr(0))
    end
    OnigMatch[m].gpos = global_pos
    if range > start
      return zr_onig_search_forward(m, start, range)
    end
    zr_onig_search_backward(m, start, range)
  end

  # The forward part of onig_search_gpos, after the anchor adjustments.
  #: (ptr, ptr, ptr) -> word
  def zr_onig_search_forward(m, start, range)
    prog = OnigMatch[m].prog
    str = OnigMatch[m].str
    text_end = OnigMatch[m].text_end
    enc = zr_onig_prog_enc(prog)
    dmax = OnigProg[prog].dmax
    s = start
    if s > str
      prev = zr_onig_prev_char_head(enc, str, s, text_end)
    else
      prev = Machine.ptr(0)
    end
    if OnigProg[prog].optimize != ONIG_OPTIMIZE_NONE
      low = Machine.slot(8)
      high = Machine.slot(8)
      low_prev = Machine.slot(8)
      if dmax != 0
        if dmax == ONIG_INFINITE_DISTANCE
          sch_range = text_end
        else
          if Machine.word(text_end - range) < dmax
            sch_range = text_end
          else
            sch_range = range + dmax
          end
        end
      else
        sch_range = range
      end
      return ONIG_MISMATCH if Machine.word(text_end - start) < OnigProg[prog].threshold_len
      if dmax != ONIG_INFINITE_DISTANCE
        while true
          return ONIG_MISMATCH if !zr_onig_forward_search_range(prog, str, text_end, s, sch_range, low, high, low_prev)
          if s < Machine.ptr(Machine.load64(low, 0))
            s = Machine.ptr(Machine.load64(low, 0))
            prev = Machine.ptr(Machine.load64(low_prev, 0))
          end
          while s <= Machine.ptr(Machine.load64(high, 0))
            r = zr_onig_try_at(m, s, prev)
            return r if r != ONIG_MISMATCH
            prev = s
            s = s + zr_onig_enclen(enc, s, text_end)
          end
          break if s >= range
        end
        return ONIG_MISMATCH
      end
      # check only.
      return ONIG_MISMATCH if !zr_onig_forward_search_range(prog, str, text_end, s, sch_range, low, high, Machine.ptr(0))
      if (OnigProg[prog].anchor & ONIG_ANCHOR_ANYCHAR_STAR) != 0
        while true
          r = zr_onig_try_at(m, s, prev)
          return r if r != ONIG_MISMATCH
          prev = s
          s = s + zr_onig_enclen(enc, s, text_end)
          if (OnigProg[prog].anchor & (ONIG_ANCHOR_LOOK_BEHIND | ONIG_ANCHOR_PREC_READ_NOT)) == 0
            while !zr_onig_newline_p(enc, prev, text_end) && s < range
              prev = s
              s = s + zr_onig_enclen(enc, s, text_end)
            end
          end
          break if s >= range
        end
        return ONIG_MISMATCH
      end
    end
    while true
      r = zr_onig_try_at(m, s, prev)
      return r if r != ONIG_MISMATCH
      prev = s
      s = s + zr_onig_enclen(enc, s, text_end)
      break if s >= range
    end
    if s == range
      # Try the end too, because /$/ can match the empty string there.
      r = zr_onig_try_at(m, s, prev)
      return r if r != ONIG_MISMATCH
    end
    ONIG_MISMATCH
  end

  # The backward part of onig_search_gpos.
  #: (ptr, ptr, ptr) -> word
  def zr_onig_search_backward(m, start, range)
    prog = OnigMatch[m].prog
    str = OnigMatch[m].str
    text_end = OnigMatch[m].text_end
    enc = zr_onig_prog_enc(prog)
    dmin = OnigProg[prog].dmin
    dmax = OnigProg[prog].dmax
    threshold_len = OnigProg[prog].threshold_len
    s = start
    if OnigProg[prog].optimize != ONIG_OPTIMIZE_NONE
      low = Machine.slot(8)
      high = Machine.slot(8)
      if range < text_end
        adjrange = zr_onig_left_adjust(enc, str, range, text_end)
      else
        adjrange = text_end
      end
      if Machine.word(text_end - range) > dmin
        min_range = range + dmin
      else
        min_range = text_end
      end
      if dmax != ONIG_INFINITE_DISTANCE && Machine.word(text_end - range) >= threshold_len
        while true
          if Machine.word(text_end - s) > dmax
            sch_start = s + dmax
          else
            sch_start = text_end
          end
          return ONIG_MISMATCH if !zr_onig_backward_search_range(prog, str, text_end, sch_start, min_range, adjrange, low, high)
          if s > Machine.ptr(Machine.load64(high, 0))
            s = Machine.ptr(Machine.load64(high, 0))
          end
          while s >= Machine.ptr(Machine.load64(low, 0))
            prev = zr_onig_prev_char_head(enc, str, s, text_end)
            r = zr_onig_try_at(m, s, prev)
            return r if r != ONIG_MISMATCH
            s = prev
            break if s == 0
          end
          break if s == 0 || s < range
        end
        return ONIG_MISMATCH
      end
      # check only.
      return ONIG_MISMATCH if Machine.word(text_end - range) < threshold_len
      if dmax != 0
        if dmax == ONIG_INFINITE_DISTANCE
          sch_start = text_end
        else
          if Machine.word(text_end - s) > dmax
            sch_start = s + dmax
            sch_start = zr_onig_left_adjust(enc, start, sch_start, text_end)
          else
            sch_start = text_end
          end
        end
      else
        sch_start = s
      end
      return ONIG_MISMATCH if !zr_onig_backward_search_range(prog, str, text_end, sch_start, min_range, adjrange, low, high)
    end
    while true
      prev = zr_onig_prev_char_head(enc, str, s, text_end)
      r = zr_onig_try_at(m, s, prev)
      return r if r != ONIG_MISMATCH
      s = prev
      break if s == 0 || s < range
    end
    ONIG_MISMATCH
  end

  # onig_search: returns the match position of `prog` in str..text_end.
  # It searches from start toward range (forward when range > start, and
  # backward if not). `region` is a word array of 2 * (num_mem + 1), or 0.
  # `limit` is in nanoseconds (0 for no limit). Returns ONIG_MISMATCH for
  # no match, and ONIGERR_TIMEOUT when the time limit is exceeded.
  #: (ptr, ptr, ptr, ptr, ptr, ptr, word) -> word
  def zr_onig_search(prog, str, text_end, start, range, region, limit)
    m = Machine.slot(OnigMatch.size)
    zr_onig_msa_init(m, prog, str, text_end, region, limit)
    r = zr_onig_search_gpos(m, start, start, range)
    zr_onig_msa_free(m)
    r
  end

  # onig_match: returns the match length at exactly `at`, ONIG_MISMATCH,
  # or an error.
  #: (ptr, ptr, ptr, ptr, ptr, word) -> word
  def zr_onig_match(prog, str, text_end, at, region, limit)
    m = Machine.slot(OnigMatch.size)
    zr_onig_msa_init(m, prog, str, text_end, region, limit)
    if region != 0
      zr_onig_region_clear(region, OnigProg[prog].num_mem)
    end
    OnigMatch[m].gpos = at
    prev = zr_onig_prev_char_head(zr_onig_prog_enc(prog), str, at, text_end)
    r = zr_onig_match_at(m, at, prev)
    zr_onig_msa_free(m)
    r
  end
end
