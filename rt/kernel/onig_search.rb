# onig_search_gpos and onig_match (regexec.c:4238-5281): the search
# drivers over match_at, with the anchor pre-checks, the exact-string
# and map searches of the optimizer, and forward_search_range /
# backward_search_range. Derived from Onigmo; the license is in
# rt/kernel/regexp.rb.
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
ONIG_MAX_PTR_NUM = 100

# The match state for a search of `prog` over str..text_end, writing
# `region` (a word array of 2 * (num_mem + 1), or 0) under a time
# `limit` in nanoseconds (0 for none). MATCH_ARG_INIT plus STACK_INIT's
# arena: the index words and the first stack, one malloc.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Word] => Void
machine def zr_onig_msa_init(m, prog, str, text_end, region, limit)
  OnigMatch.set_prog(m, prog)
  OnigMatch.set_code(m, prog + OnigProg.code_off(prog))
  OnigMatch.set_enc(m, zr_onig_prog_enc(prog))
  OnigMatch.set_options(m, OnigProg.options(prog))
  OnigMatch.set_case_fold(m, OnigProg.case_fold_flag(prog))
  num_mem = OnigProg.num_mem(prog)
  OnigMatch.set_num_mem(m, num_mem)
  OnigMatch.set_pop_level(m, OnigProg.pop_level(prog))
  OnigMatch.set_bt_mem_start(m, OnigProg.bt_mem_start(prog))
  OnigMatch.set_bt_mem_end(m, OnigProg.bt_mem_end(prog))
  OnigMatch.set_str(m, str)
  OnigMatch.set_text_end(m, text_end)
  OnigMatch.set_region(m, region)
  OnigMatch.set_mopts(m, 0)
  OnigMatch.set_stack_p(m, Machine.ptr(0))
  OnigMatch.set_stack_n(m, 0)
  OnigMatch.set_counter(m, 0)
  OnigMatch.set_end_time(m, 0)
  OnigMatch.set_limit(m, limit)
  OnigMatch.set_best_len(m, ONIG_MISMATCH)
  # MATCH_ARG_INIT_MATCH_CACHE
  OnigMatch.set_match_cache_status(m, ONIG_MATCH_CACHE_STATUS_UNINIT)
  OnigMatch.set_num_fails(m, 0)
  OnigMatch.set_num_cache_opcodes(m, ONIG_NUM_CACHE_OPCODES_UNINIT)
  OnigMatch.set_cache_opcodes(m, Machine.ptr(0))
  OnigMatch.set_num_cache_points(m, 0)
  OnigMatch.set_match_cache_buf(m, Machine.ptr(0))
  num_repeat = OnigProg.num_repeat(prog)
  # ADD_NUMMEM: group 0 has a slot too, for \g<0>.
  words = num_repeat + ((num_mem + 1) * 2)
  arena = malloc((words * 8) + (ONIG_INIT_MATCH_STACK_SIZE * OnigStk.size))
  abort() if arena == 0
  OnigMatch.set_repeat_stk(m, arena)
  OnigMatch.set_mem_start_stk(m, arena + (num_repeat * 8))
  OnigMatch.set_mem_end_stk(m, arena + (num_repeat * 8) + ((num_mem + 1) * 8))
  OnigMatch.set_stk_alloc(m, arena + (words * 8))
end

# MATCH_ARG_FREE (the match cache's rows and bits with it) and the arena.
sig [Ptr] => Void
machine def zr_onig_msa_free(m)
  if OnigMatch.stack_p(m) != 0
    free(OnigMatch.stack_p(m))
  end
  if OnigMatch.cache_opcodes(m) != 0
    free(OnigMatch.cache_opcodes(m))
  end
  if OnigMatch.match_cache_buf(m) != 0
    free(OnigMatch.match_cache_buf(m))
  end
  free(OnigMatch.repeat_stk(m))
end

# onig_region_resize_clear: every position ONIG_REGION_NOTPOS.
sig [Ptr, Word] => Void
machine def zr_onig_region_clear(region, num_mem)
  i = 0
  while i <= num_mem
    Machine.store64(region + (i * 16), 0, ONIG_REGION_NOTPOS)
    Machine.store64(region + (i * 16), 8, ONIG_REGION_NOTPOS)
    i += 1
  end
end

# The optimizer's exact bytes and their end.
sig [Ptr] => Ptr
machine def zr_onig_exact(prog)
  prog + OnigProg.exact_off(prog)
end

sig [Ptr] => Ptr
machine def zr_onig_exact_end(prog)
  prog + OnigProg.exact_off(prog) + OnigProg.exact_len(prog)
end

sig [Ptr] => Ptr
machine def zr_onig_map(prog)
  prog + OnigProg.map_off(prog)
end

sig [Ptr, Word] => Word
machine def zr_onig_map_at(prog, c)
  Machine.word(Machine.load8(prog + OnigProg.map_off(prog) + c, 0))
end

# slow_search.
sig [Word, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_slow_search(enc, target, target_end, text, text_end, text_range)
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
sig [Word, Word, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_slow_search_ic(enc, flag, target, target_end, text, text_end, text_range)
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
sig [Word, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_slow_search_backward(enc, target, target_end, text, adjust_text, text_end, text_start)
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
sig [Word, Word, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_slow_search_backward_ic(enc, flag, target, target_end, text, adjust_text, text_end, text_start)
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

# bm_search_notrev: Sunday's quick search applied to a multibyte string.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_bm_search_notrev(prog, target, target_end, text, text_end, text_range)
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
    skip = zr_onig_map_at(prog, Machine.word(Machine.load8(se, 1)))
    t = s
    while true
      s = s + zr_onig_enclen(enc, s, e)
      break if !(Machine.word(s - t) < skip && s < e)
    end
  end
  Machine.ptr(0)
end

# bm_search: Sunday's quick search.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_bm_search(prog, target, target_end, text, text_end, text_range)
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
    s = s + zr_onig_map_at(prog, Machine.word(Machine.load8(s, 1)))
  end
  Machine.ptr(0)
end

# bm_search_notrev_ic.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_bm_search_notrev_ic(prog, target, target_end, text, text_end, text_range)
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
    return s if zr_onig_str_lower_case_match(enc, OnigProg.case_fold_flag(prog), target, target_end, s, se + 1)
    break if s + 1 >= e
    skip = zr_onig_map_at(prog, Machine.word(Machine.load8(se, 1)))
    t = s
    while true
      s = s + zr_onig_enclen(enc, s, e)
      break if !(Machine.word(s - t) < skip && s < e)
    end
  end
  Machine.ptr(0)
end

# bm_search_ic.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_bm_search_ic(prog, target, target_end, text, text_end, text_range)
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
    return p if zr_onig_str_lower_case_match(enc, OnigProg.case_fold_flag(prog), target, target_end, p, s + 1)
    break if s + 1 >= e
    s = s + zr_onig_map_at(prog, Machine.word(Machine.load8(s, 1)))
  end
  Machine.ptr(0)
end

# map_search.
sig [Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_map_search(prog, text, text_range, text_end)
  enc = zr_onig_prog_enc(prog)
  s = text
  while s < text_range
    return s if zr_onig_map_at(prog, Machine.word(Machine.load8(s, 0))) != 0
    s = s + zr_onig_enclen(enc, s, text_end)
  end
  Machine.ptr(0)
end

# map_search_backward.
sig [Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_map_search_backward(prog, text, adjust_text, text_start, text_end)
  enc = zr_onig_prog_enc(prog)
  s = text_start
  while s >= text
    return s if zr_onig_map_at(prog, Machine.word(Machine.load8(s, 0))) != 0
    s = zr_onig_prev_char_head(enc, adjust_text, s, text_end)
    break if s == 0
  end
  Machine.ptr(0)
end

# The optimizer's search from p forward, by reg->optimize.
sig [Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_forward_find(prog, p, text_end, range)
  optimize = OnigProg.optimize(prog)
  enc = zr_onig_prog_enc(prog)
  exact = zr_onig_exact(prog)
  exact_end = zr_onig_exact_end(prog)
  return zr_onig_slow_search(enc, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT
  return zr_onig_slow_search_ic(enc, OnigProg.case_fold_flag(prog), exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_IC
  return zr_onig_bm_search(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM
  return zr_onig_bm_search_notrev(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV
  return zr_onig_bm_search_ic(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_IC
  return zr_onig_bm_search_notrev_ic(prog, exact, exact_end, p, text_end, range) if optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC
  return zr_onig_map_search(prog, p, range, text_end) if optimize == ONIG_OPTIMIZE_MAP
  Machine.ptr(0)
end

# forward_search_range: whether the optimizer finds a possible match
# start from s before range; the cells `low`, `high` and (when not 0)
# `low_prev` take the match window.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Bool
machine def zr_onig_forward_search_range(prog, str, text_end, s, range, low, high, low_prev)
  enc = zr_onig_prog_enc(prog)
  dmin = OnigProg.dmin(prog)
  dmax = OnigProg.dmax(prog)
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
    elsif OnigProg.sub_anchor(prog) == ONIG_ANCHOR_BEGIN_LINE
      if p != str
        prev = zr_onig_prev_char_head(enc, pprev != 0 ? pprev : str, p, text_end)
        again = true if !zr_onig_newline_p(enc, prev, text_end)
      end
    elsif OnigProg.sub_anchor(prog) == ONIG_ANCHOR_END_LINE
      # The empty line at the end of the text is a line
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
    # no needs to adjust *high, *high is used as range check only
    if Machine.word(p - str) < dmin
      Machine.store64(high, 0, Machine.word(str))
    else
      Machine.store64(high, 0, Machine.word(p - dmin))
    end
  end
  true
end

# The optimizer's search from p backward, by reg->optimize.
sig [Ptr, Ptr, Ptr, Ptr, Ptr] => Ptr
machine def zr_onig_backward_find(prog, p, range, adjrange, text_end)
  optimize = OnigProg.optimize(prog)
  enc = zr_onig_prog_enc(prog)
  exact = zr_onig_exact(prog)
  exact_end = zr_onig_exact_end(prog)
  if optimize == ONIG_OPTIMIZE_EXACT || optimize == ONIG_OPTIMIZE_EXACT_BM || optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV
    return zr_onig_slow_search_backward(enc, exact, exact_end, range, adjrange, text_end, p)
  end
  if optimize == ONIG_OPTIMIZE_EXACT_IC || optimize == ONIG_OPTIMIZE_EXACT_BM_IC || optimize == ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC
    return zr_onig_slow_search_backward_ic(enc, OnigProg.case_fold_flag(prog), exact, exact_end, range, adjrange, text_end, p)
  end
  return zr_onig_map_search_backward(prog, range, adjrange, p, text_end) if optimize == ONIG_OPTIMIZE_MAP
  Machine.ptr(0)
end

# backward_search_range.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, Ptr] => Bool
machine def zr_onig_backward_search_range(prog, str, text_end, s, range, adjrange, low, high)
  enc = zr_onig_prog_enc(prog)
  dmin = OnigProg.dmin(prog)
  dmax = OnigProg.dmax(prog)
  return false if dmin > Machine.word(text_end - str)
  p = s
  while true
    p = zr_onig_backward_find(prog, p, range, adjrange, text_end)
    return false if p == 0
    again = false
    if OnigProg.sub_anchor(prog) == ONIG_ANCHOR_BEGIN_LINE
      if p != str
        prev = zr_onig_prev_char_head(enc, str, p, text_end)
        if !zr_onig_newline_p(enc, prev, text_end)
          p = prev
          again = true
        end
      end
    elsif OnigProg.sub_anchor(prog) == ONIG_ANCHOR_END_LINE
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

# MATCH_AND_RETURN_CHECK: match_at at s; the match's position, or
# ONIG_MISMATCH to go on, or an error to stop with.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_onig_try_at(m, s, prev)
  r = zr_onig_match_at(m, s, prev)
  return Machine.word(s - OnigMatch.str(m)) if r >= 0
  r
end

# onig_search_gpos over the match state `m` (zr_onig_msa_init'd), with
# global_pos for \G. The answer is the match position, ONIG_MISMATCH, or
# an error code.
sig [Ptr, Ptr, Ptr, Ptr] => Word
machine def zr_onig_search_gpos(m, global_pos, start, range)
  prog = OnigMatch.prog(m)
  str = OnigMatch.str(m)
  text_end = OnigMatch.text_end(m)
  enc = zr_onig_prog_enc(prog)
  region = OnigMatch.region(m)
  if region != 0
    zr_onig_region_clear(region, OnigProg.num_mem(prog))
  end
  return ONIG_MISMATCH if start > text_end || start < str
  anchor = OnigProg.anchor(prog)
  # anchor optimize: resume search range
  if anchor != 0 && str < text_end
    anchor_dmin = OnigProg.anchor_dmin(prog)
    anchor_dmax = OnigProg.anchor_dmax(prog)
    end_buf = false
    min_semi_end = text_end
    max_semi_end = text_end
    if (anchor & ONIG_ANCHOR_BEGIN_POSITION) != 0 || (anchor & ONIG_ANCHOR_ANYCHAR_STAR_ML) != 0 && (anchor & (ONIG_ANCHOR_BEGIN_BUF | ONIG_ANCHOR_END_BUF | ONIG_ANCHOR_SEMI_END_BUF)) == 0
      # search start-position only
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
      # search str-position only
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
        # If start == range, match with empty at end. Backward search is used.
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
    # empty string
    return ONIG_MISMATCH if OnigProg.threshold_len(prog) != 0
    OnigMatch.set_gpos(m, start)
    return zr_onig_try_at(m, start, Machine.ptr(0))
  end
  OnigMatch.set_gpos(m, global_pos)
  if range > start
    return zr_onig_search_forward(m, start, range)
  end
  zr_onig_search_backward(m, start, range)
end

# The forward half of onig_search_gpos, after the anchor adjustments.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_onig_search_forward(m, start, range)
  prog = OnigMatch.prog(m)
  str = OnigMatch.str(m)
  text_end = OnigMatch.text_end(m)
  enc = zr_onig_prog_enc(prog)
  dmax = OnigProg.dmax(prog)
  s = start
  if s > str
    prev = zr_onig_prev_char_head(enc, str, s, text_end)
  else
    prev = Machine.ptr(0)
  end
  if OnigProg.optimize(prog) != ONIG_OPTIMIZE_NONE
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
    return ONIG_MISMATCH if Machine.word(text_end - start) < OnigProg.threshold_len(prog)
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
    if (OnigProg.anchor(prog) & ONIG_ANCHOR_ANYCHAR_STAR) != 0
      while true
        r = zr_onig_try_at(m, s, prev)
        return r if r != ONIG_MISMATCH
        prev = s
        s = s + zr_onig_enclen(enc, s, text_end)
        if (OnigProg.anchor(prog) & (ONIG_ANCHOR_LOOK_BEHIND | ONIG_ANCHOR_PREC_READ_NOT)) == 0
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
    # because empty match with /$/.
    r = zr_onig_try_at(m, s, prev)
    return r if r != ONIG_MISMATCH
  end
  ONIG_MISMATCH
end

# The backward half of onig_search_gpos.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_onig_search_backward(m, start, range)
  prog = OnigMatch.prog(m)
  str = OnigMatch.str(m)
  text_end = OnigMatch.text_end(m)
  enc = zr_onig_prog_enc(prog)
  dmin = OnigProg.dmin(prog)
  dmax = OnigProg.dmax(prog)
  threshold_len = OnigProg.threshold_len(prog)
  s = start
  if OnigProg.optimize(prog) != ONIG_OPTIMIZE_NONE
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

# onig_search: the match position of `prog` in str..text_end searching
# from start toward range (forward when range > start, else backward),
# `region` a word array of 2 * (num_mem + 1) or 0, under `limit`
# nanoseconds (0 for none); ONIG_MISMATCH for none, ONIGERR_TIMEOUT
# when the limit passed.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Ptr, Word] => Word
machine def zr_onig_search(prog, str, text_end, start, range, region, limit)
  m = Machine.slot(OnigMatch.size)
  zr_onig_msa_init(m, prog, str, text_end, region, limit)
  r = zr_onig_search_gpos(m, start, start, range)
  zr_onig_msa_free(m)
  r
end

# onig_match: the length matched at `at` exactly, ONIG_MISMATCH, or an error.
sig [Ptr, Ptr, Ptr, Ptr, Ptr, Word] => Word
machine def zr_onig_match(prog, str, text_end, at, region, limit)
  m = Machine.slot(OnigMatch.size)
  zr_onig_msa_init(m, prog, str, text_end, region, limit)
  if region != 0
    zr_onig_region_clear(region, OnigProg.num_mem(prog))
  end
  OnigMatch.set_gpos(m, at)
  prev = zr_onig_prev_char_head(zr_onig_prog_enc(prog), str, at, text_end)
  r = zr_onig_match_at(m, at, prev)
  zr_onig_msa_free(m)
  r
end
