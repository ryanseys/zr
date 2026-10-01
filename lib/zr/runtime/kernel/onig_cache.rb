module Zr::Kern
  # The match cache (USE_MATCH_CACHE, regexec.c:234-880 and 2118-2310).
  # When the backtrack count of a match gets to the subject length, the
  # matcher counts and numbers the program's cacheable opcodes. Then it
  # records each failed (cache point, position) pair in a bit array, so a
  # later visit fails immediately. This keeps CRuby's matching linear on
  # patterns like /(a+)+$/. Derived from Onigmo; the license is in
  # lib/zr/runtime/kernel/regexp.rb.
  Libc.import :memset, [Ptr, I32, Word] => Ptr

  ONIG_NUM_CACHE_OPCODES_UNINIT = 1
  ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE = 0 - 1
  ONIG_MATCH_CACHE_STATUS_UNINIT = 1
  ONIG_MATCH_CACHE_STATUS_INIT = 2
  ONIG_MATCH_CACHE_STATUS_DISABLED = 0 - 1
  ONIG_MATCH_CACHE_STATUS_ENABLED = 0
  ONIG_LONG_MAX_LIMIT = 1 << 62
  STK_MATCH_CACHE_POINT = 3328
  STK_ATOMIC_MATCH_CACHE_POINT = 3584

  # OnigCacheOpcode.
  OnigCacheOp = layout addr: Ptr, cache_point: Word, outer_repeat_mem: Word,
    at_outer: Word, in_outer: Word, lookaround_nesting: Word, match_addr: Ptr

  # The position after the operands of an opcode that has no cache point
  # and needs no special handling, or 0 for all other opcodes.
  sig [Ptr, Word, Ptr, Ptr] => Ptr
  def zr_onig_cache_skip(m, op, p, pend)
    if op == OP_FINISH || op == OP_END || op == OP_ANYCHAR || op == OP_ANYCHAR_ML || op == OP_KEEP || op == OP_FAIL || op == OP_POP
      return p
    end
    if op >= OP_WORD && op <= OP_BEGIN_POSITION
      return p
    end
    return p + 1 if op == OP_EXACT1
    return p + 2 if op == OP_EXACT2 || op == OP_EXACTMB2N1
    return p + 3 if op == OP_EXACT3
    return p + 4 if op == OP_EXACT4 || op == OP_EXACTMB2N2
    return p + 5 if op == OP_EXACT5
    return p + 6 if op == OP_EXACTMB2N3
    return p + 4 + zr_onig_get_i32(p) if op == OP_EXACTN || op == OP_EXACTN_IC || op == OP_CCLASS_MB || op == OP_CCLASS_MB_NOT
    return p + 4 if op == OP_LOOK_BEHIND
    return p + 4 + (zr_onig_get_i32(p) * 2) if op == OP_EXACTMB2N
    return p + 4 + (zr_onig_get_i32(p) * 3) if op == OP_EXACTMB3N
    return p + 8 + (zr_onig_get_i32(p) * zr_onig_get_i32(p + 4)) if op == OP_EXACTMBN
    return p + zr_onig_enclen(OnigMatch.enc(m), p, pend) if op == OP_EXACT1_IC
    return p + ONIG_SIZE_BITSET if op == OP_CCLASS || op == OP_CCLASS_NOT
    return p + ONIG_SIZE_BITSET + 4 + zr_onig_get_i32(p + ONIG_SIZE_BITSET) if op == OP_CCLASS_MIX || op == OP_CCLASS_MIX_NOT
    return p + ONIG_SIZE_RELADDR if op == OP_JUMP
    return p + ONIG_SIZE_MEMNUM if op >= OP_NULL_CHECK_START && op <= OP_NULL_CHECK_END_MEMST_PUSH
    Machine.ptr(0)
  end

  # count_num_cache_opcodes_inner: the slot `pp` steps through the code,
  # and the slot `np` contains the count. Returns 0, or an error. A count
  # of NUM_CACHE_OPCODES_IMPOSSIBLE shows that the program cannot be
  # cached.
  sig [Ptr, Word, Word, Ptr, Ptr] => Word
  def zr_onig_count_cache_opcodes(m, current_repeat_mem, lookaround_nesting, pp, np)
    p = Machine.ptr(Machine.load64(pp, 0))
    pend = OnigMatch.code(m) + OnigProg.code_len(OnigMatch.prog(m))
    n = Machine.load64(np, 0)
    while p < pend
      op = Machine.word(Machine.load8(p, 0))
      p = p + 1
      q = zr_onig_cache_skip(m, op, p, pend)
      if q != 0
        p = q
      elsif op == OP_ANYCHAR_STAR || op == OP_ANYCHAR_ML_STAR
        n += 1
      elsif op == OP_ANYCHAR_STAR_PEEK_NEXT || op == OP_ANYCHAR_ML_STAR_PEEK_NEXT
        p = p + 1
        n += 1
      elsif op >= OP_BACKREF1 && op <= OP_BACKREF_WITH_LEVEL
        Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
        return 0
      elsif op >= OP_MEMORY_START && op <= OP_MEMORY_END_REC
        p = p + ONIG_SIZE_MEMNUM
        if lookaround_nesting != 0
          # A memory (capture) in look-around is found.
          Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
          return 0
        end
      elsif op == OP_PUSH
        p = p + ONIG_SIZE_RELADDR
        n += 1
      elsif op == OP_PUSH_IF_PEEK_NEXT
        p = p + ONIG_SIZE_RELADDR + 1
        n += 1
      elsif op == OP_REPEAT || op == OP_REPEAT_NG
        if current_repeat_mem != 0 - 1
          # A nested OP_REPEAT is not yet supported.
          Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
          return 0
        end
        repeat_mem = zr_onig_get_memnum(p)
        p = p + ONIG_SIZE_MEMNUM + ONIG_SIZE_RELADDR
        lower = zr_onig_repeat_range(m, repeat_mem, 0)
        upper = zr_onig_repeat_range(m, repeat_mem, 1)
        cell = Machine.slot(8)
        Machine.store64(cell, 0, Machine.word(p))
        if lower == 0 && upper == 0
          dummy = Machine.slot(8)
          Machine.store64(dummy, 0, 0)
          result = zr_onig_count_cache_opcodes(m, repeat_mem, lookaround_nesting, cell, dummy)
          if result < 0 || Machine.load64(dummy, 0) < 0
            Machine.store64(np, 0, n)
            return result
          end
        else
          if lower == 0
            n += 1
          end
          Machine.store64(np, 0, n)
          result = zr_onig_count_cache_opcodes(m, repeat_mem, lookaround_nesting, cell, np)
          n = Machine.load64(np, 0)
          if result < 0 || n < 0
            return result
          end
          if lower < upper
            n += 1
          end
        end
        p = Machine.ptr(Machine.load64(cell, 0))
      elsif op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG
        repeat_mem = zr_onig_get_memnum(p)
        p = p + ONIG_SIZE_MEMNUM
        if repeat_mem != current_repeat_mem
          # A lone or invalid OP_REPEAT_INC is found.
          Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
          return 0
        end
        break
      elsif op == OP_PUSH_POS || op == OP_PUSH_POS_NOT || op == OP_PUSH_LOOK_BEHIND_NOT
        if lookaround_nesting < 0
          # A look-around nested in an atomic grouping is found.
          Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
          return 0
        end
        if op == OP_PUSH_POS_NOT
          p = p + ONIG_SIZE_RELADDR
        elsif op == OP_PUSH_LOOK_BEHIND_NOT
          p = p + ONIG_SIZE_RELADDR + 4
        end
        cell = Machine.slot(8)
        Machine.store64(cell, 0, Machine.word(p))
        Machine.store64(np, 0, n)
        result = zr_onig_count_cache_opcodes(m, current_repeat_mem, lookaround_nesting + 1, cell, np)
        n = Machine.load64(np, 0)
        if result < 0 || n < 0
          return result
        end
        p = Machine.ptr(Machine.load64(cell, 0))
      elsif op == OP_PUSH_STOP_BT
        if lookaround_nesting != 0
          # A nested atomic grouping is found.
          Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
          return 0
        end
        cell = Machine.slot(8)
        Machine.store64(cell, 0, Machine.word(p))
        Machine.store64(np, 0, n)
        result = zr_onig_count_cache_opcodes(m, current_repeat_mem, 0 - 1, cell, np)
        n = Machine.load64(np, 0)
        if result < 0 || n < 0
          return result
        end
        p = Machine.ptr(Machine.load64(cell, 0))
      elsif op == OP_POP_POS || op == OP_FAIL_POS || op == OP_FAIL_LOOK_BEHIND_NOT || op == OP_POP_STOP_BT
        break
      elsif op == OP_REPEAT_INC_SG || op == OP_REPEAT_INC_NG_SG || op == OP_PUSH_ABSENT_POS || op == OP_ABSENT_END || op == OP_ABSENT || op == OP_CALL || op == OP_RETURN || op == OP_CONDITION
        Machine.store64(np, 0, ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE)
        return 0
      else
        return ONIGERR_UNDEFINED_BYTECODE
      end
    end
    Machine.store64(pp, 0, Machine.word(p))
    Machine.store64(np, 0, n)
    0
  end

  # count_num_cache_opcodes: stores the program's count in `np`.
  sig [Ptr, Ptr] => Word
  def zr_onig_count_num_cache_opcodes(m, np)
    pp = Machine.slot(8)
    Machine.store64(pp, 0, Machine.word(OnigMatch.code(m)))
    Machine.store64(np, 0, 0)
    result = zr_onig_count_cache_opcodes(m, 0 - 1, 0, pp, np)
    pend = OnigMatch.code(m) + OnigProg.code_len(OnigMatch.prog(m))
    if result == 0 && Machine.load64(np, 0) >= 0 && Machine.ptr(Machine.load64(pp, 0)) != pend
      return ONIGERR_UNDEFINED_BYTECODE
    end
    result
  end

  # INC_CACHE_OPCODES: writes one cache opcode entry at the slot `cop` (0
  # for a dry run) for the opcode at pbegin. Returns the next cache point.
  sig [Ptr, Ptr, Word, Word, Word] => Word
  def zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
    return cache_point if cop == 0
    row = Machine.ptr(Machine.load64(cop, 0))
    return cache_point if row == 0
    OnigCacheOp.set_addr(row, pbegin)
    OnigCacheOp.set_cache_point(row, cache_point)
    OnigCacheOp.set_outer_repeat_mem(row, current_repeat_mem)
    OnigCacheOp.set_at_outer(row, 0)
    OnigCacheOp.set_in_outer(row, 0)
    OnigCacheOp.set_lookaround_nesting(row, lookaround_nesting)
    OnigCacheOp.set_match_addr(row, Machine.ptr(0))
    Machine.store64(cop, 0, Machine.word(row + OnigCacheOp.size))
    cache_point + (lookaround_nesting != 0 ? 2 : 1)
  end

  # Sets `match_addr` in the entries from `first` up to the entry at the
  # slot `cop`, if they have none yet (the end of a look-around or atomic
  # group).
  sig [Ptr, Ptr, Ptr] => Void
  def zr_onig_cache_rows_match_addr(first, cop, match_addr)
    row = first
    stop = Machine.ptr(Machine.load64(cop, 0))
    while row < stop
      if OnigCacheOp.match_addr(row) == 0
        OnigCacheOp.set_match_addr(row, match_addr)
      end
      row = row + OnigCacheOp.size
    end
  end

  # init_cache_opcodes_inner: writes the entries from the slot `cop` (a
  # pointer to the next entry, or 0 for a dry run). The slot `pp` steps
  # through the code, and the slot `npoints` counts the cache points.
  sig [Ptr, Word, Word, Ptr, Ptr, Ptr] => Word
  def zr_onig_init_cache_opcodes(m, current_repeat_mem, lookaround_nesting, cop, pp, npoints)
    p = Machine.ptr(Machine.load64(pp, 0))
    pend = OnigMatch.code(m) + OnigProg.code_len(OnigMatch.prog(m))
    cache_point = Machine.load64(npoints, 0)
    while p < pend
      pbegin = p
      op = Machine.word(Machine.load8(p, 0))
      p = p + 1
      q = zr_onig_cache_skip(m, op, p, pend)
      if q != 0
        p = q
      elsif op == OP_ANYCHAR_STAR || op == OP_ANYCHAR_ML_STAR
        cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
      elsif op == OP_ANYCHAR_STAR_PEEK_NEXT || op == OP_ANYCHAR_ML_STAR_PEEK_NEXT
        p = p + 1
        cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
      elsif op >= OP_BACKREF1 && op <= OP_BACKREF_WITH_LEVEL
        return ONIGERR_UNEXPECTED_BYTECODE
      elsif op >= OP_MEMORY_START && op <= OP_MEMORY_END_REC
        p = p + ONIG_SIZE_MEMNUM
        return ONIGERR_UNEXPECTED_BYTECODE if lookaround_nesting != 0
      elsif op == OP_PUSH
        p = p + ONIG_SIZE_RELADDR
        cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
      elsif op == OP_PUSH_IF_PEEK_NEXT
        p = p + ONIG_SIZE_RELADDR + 1
        cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
      elsif op == OP_REPEAT || op == OP_REPEAT_NG
        repeat_mem = zr_onig_get_memnum(p)
        p = p + ONIG_SIZE_MEMNUM + ONIG_SIZE_RELADDR
        lower = zr_onig_repeat_range(m, repeat_mem, 0)
        upper = zr_onig_repeat_range(m, repeat_mem, 1)
        cell = Machine.slot(8)
        Machine.store64(cell, 0, Machine.word(p))
        if lower == 0 && upper == 0
          dummy = Machine.slot(8)
          Machine.store64(dummy, 0, 0)
          dummy_cop = Machine.slot(8)
          Machine.store64(dummy_cop, 0, 0)
          result = zr_onig_init_cache_opcodes(m, repeat_mem, lookaround_nesting, dummy_cop, cell, dummy)
          return result if result != 0
        else
          if lower == 0
            cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
          end
          in_repeat = Machine.slot(8)
          Machine.store64(in_repeat, 0, 0)
          at_repeat = cache_point
          first = Machine.ptr(Machine.load64(cop, 0))
          result = zr_onig_init_cache_opcodes(m, repeat_mem, lookaround_nesting, cop, cell, in_repeat)
          return result if result != 0
          points_in_repeat = Machine.load64(in_repeat, 0)
          if lower < upper
            cache_point = zr_onig_cache_row(cop, pbegin, cache_point, current_repeat_mem, lookaround_nesting)
            cache_point -= lookaround_nesting != 0 ? 2 : 1
          end
          repeat_bounds = upper == 2147483647 ? 1 : upper - lower
          cache_point += (points_in_repeat * lower) + ((points_in_repeat + (lookaround_nesting != 0 ? 2 : 1)) * repeat_bounds)
          row = first
          stop = Machine.ptr(Machine.load64(cop, 0))
          while row != 0 && row < stop
            OnigCacheOp.set_at_outer(row, at_repeat)
            OnigCacheOp.set_in_outer(row, points_in_repeat)
            row = row + OnigCacheOp.size
          end
        end
        p = Machine.ptr(Machine.load64(cell, 0))
      elsif op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG
        p = p + ONIG_SIZE_MEMNUM
        break
      elsif op == OP_PUSH_POS || op == OP_PUSH_POS_NOT || op == OP_PUSH_LOOK_BEHIND_NOT || op == OP_PUSH_STOP_BT
        if op == OP_PUSH_POS_NOT
          p = p + ONIG_SIZE_RELADDR
        elsif op == OP_PUSH_LOOK_BEHIND_NOT
          p = p + ONIG_SIZE_RELADDR + 4
        end
        first = Machine.ptr(Machine.load64(cop, 0))
        cell = Machine.slot(8)
        Machine.store64(cell, 0, Machine.word(p))
        Machine.store64(npoints, 0, cache_point)
        nesting = op == OP_PUSH_STOP_BT ? 0 - 1 : lookaround_nesting + 1
        result = zr_onig_init_cache_opcodes(m, current_repeat_mem, nesting, cop, cell, npoints)
        return result if result != 0
        cache_point = Machine.load64(npoints, 0)
        p = Machine.ptr(Machine.load64(cell, 0))
        if first != 0
          zr_onig_cache_rows_match_addr(first, cop, p - 1)
        end
      elsif op == OP_POP_POS || op == OP_FAIL_POS || op == OP_FAIL_LOOK_BEHIND_NOT || op == OP_POP_STOP_BT
        break
      elsif op == OP_REPEAT_INC_SG || op == OP_REPEAT_INC_NG_SG || op == OP_ABSENT_END || op == OP_ABSENT || op == OP_CALL || op == OP_RETURN || op == OP_CONDITION
        return ONIGERR_UNEXPECTED_BYTECODE
      else
        return ONIGERR_UNDEFINED_BYTECODE
      end
    end
    Machine.store64(pp, 0, Machine.word(p))
    Machine.store64(npoints, 0, cache_point)
    0
  end

  # init_cache_opcodes: writes the entries at `rows`, and stores the
  # number of cache points in the slot `npoints`.
  sig [Ptr, Ptr, Ptr] => Word
  def zr_onig_init_cache_rows(m, rows, npoints)
    pp = Machine.slot(8)
    Machine.store64(pp, 0, Machine.word(OnigMatch.code(m)))
    cop = Machine.slot(8)
    Machine.store64(cop, 0, Machine.word(rows))
    Machine.store64(npoints, 0, 0)
    result = zr_onig_init_cache_opcodes(m, 0 - 1, 0, cop, pp, npoints)
    pend = OnigMatch.code(m) + OnigProg.code_len(OnigMatch.prog(m))
    if result == 0 && Machine.ptr(Machine.load64(pp, 0)) != pend
      return ONIGERR_UNDEFINED_BYTECODE
    end
    result
  end

  # bsearch_cache_opcodes: the entry index nearest to the opcode at p.
  sig [Ptr, Word, Ptr] => Word
  def zr_onig_bsearch_cache_opcodes(rows, n, p)
    l = 0
    r = n - 1
    mid = 0
    while l <= r
      mid = (l + r) / 2
      addr = OnigCacheOp.addr(rows + (mid * OnigCacheOp.size))
      break if addr == p
      if addr < p
        l = mid + 1
      else
        r = mid - 1
      end
    end
    mid
  end

  # find_cache_point: the cache point of the opcode at p in the current
  # repeat count, or -1 for none. Stores its entry in the slot `cop`.
  sig [Ptr, Ptr, Ptr] => Word
  def zr_onig_find_cache_point(m, p, cop)
    rows = OnigMatch.cache_opcodes(m)
    n = OnigMatch.num_cache_opcodes(m)
    op = Machine.word(Machine.load8(p, 0))
    is_inc = op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG
    mid = zr_onig_bsearch_cache_opcodes(rows, n, p)
    row = rows + (mid * OnigCacheOp.size)
    if !(mid >= 0 && mid < n && OnigCacheOp.addr(row) == p)
      return 0 - 1
    end
    Machine.store64(cop, 0, Machine.word(row))
    cache_point = OnigCacheOp.cache_point(row)
    outer = OnigCacheOp.outer_repeat_mem(row)
    return cache_point if outer == 0 - 1
    at_outer = OnigCacheOp.at_outer(row)
    in_outer = OnigCacheOp.in_outer(row)
    lower = zr_onig_repeat_range(m, outer, 0)
    upper = zr_onig_repeat_range(m, outer, 1)
    stkp = zr_onig_stk_at(m, Machine.load64(OnigMatch.repeat_stk(m) + (outer * 8), 0))
    count = is_inc ? OnigStk.a(stkp) - 1 : OnigStk.a(stkp)
    if count < lower
      return at_outer + (in_outer * count) + cache_point
    end
    if upper == 2147483647
      return at_outer + (in_outer * (lower - (is_inc ? 1 : 0))) + (is_inc ? 0 : 1) + cache_point
    end
    at_outer + (in_outer * (lower - 1)) + ((in_outer + 1) * (count - lower + 1)) + cache_point
  end

  # check_extended_match_cache_point.
  sig [Ptr, Word, Word] => Bool
  def zr_onig_check_extended_cache_point(buf, index, mask)
    if (mask & 128) != 0
      return (Machine.word(Machine.load8(buf + index, 1)) & 1) != 0
    end
    (Machine.word(Machine.load8(buf + index, 0)) & (mask << 1)) != 0
  end

  # memoize_extended_match_cache_point.
  sig [Ptr, Word, Word] => Void
  def zr_onig_memoize_extended_cache_point(buf, index, mask)
    Machine.store8(buf + index, 0, Machine.i8(Machine.word(Machine.load8(buf + index, 0)) | mask))
    if (mask & 128) != 0
      Machine.store8(buf + index, 1, Machine.i8(Machine.word(Machine.load8(buf + index, 1)) | 1))
    else
      Machine.store8(buf + index, 0, Machine.i8(Machine.word(Machine.load8(buf + index, 0)) | (mask << 1)))
    end
  end

  # MEMOIZE_MATCH_CACHE_POINT: records the cache point of a popped stack
  # entry.
  sig [Ptr, Ptr] => Void
  def zr_onig_memoize_cache_point(m, stk)
    type = OnigStk.type(stk)
    if type == STK_MATCH_CACHE_POINT
      buf = OnigMatch.match_cache_buf(m)
      index = OnigStk.a(stk)
      Machine.store8(buf + index, 0, Machine.i8(Machine.word(Machine.load8(buf + index, 0)) | OnigStk.b(stk)))
    elsif type == STK_ATOMIC_MATCH_CACHE_POINT
      zr_onig_memoize_extended_cache_point(OnigMatch.match_cache_buf(m), OnigStk.a(stk), OnigStk.b(stk))
    end
  end

  # MEMOIZE_LOOKAROUND_MATCH_CACHE_POINT: voids a cache point that a
  # look-around leaves, and records it in the extended form.
  sig [Ptr, Ptr] => Void
  def zr_onig_memoize_lookaround_cache_point(m, stk)
    if OnigStk.type(stk) == STK_MATCH_CACHE_POINT
      OnigStk.set_type(stk, STK_VOID)
      zr_onig_memoize_extended_cache_point(OnigMatch.match_cache_buf(m), OnigStk.a(stk), OnigStk.b(stk))
    end
  end

  # STACK_STOP_BT_FAIL: pops down to the atomic group's mark, and records
  # the cache points above it in the extended form.
  sig [Ptr] => Void
  def zr_onig_stack_stop_bt_fail(m)
    stk = OnigMatch.stk(m)
    while true
      stk = stk - OnigStk.size
      type = OnigStk.type(stk)
      if type == STK_STOP_BT
        OnigStk.set_type(stk, STK_VOID)
        break
      end
      if type == STK_MATCH_CACHE_POINT
        zr_onig_memoize_extended_cache_point(OnigMatch.match_cache_buf(m), OnigStk.a(stk), OnigStk.b(stk))
      end
    end
    OnigMatch.set_stk(m, stk)
  end

  # STACK_PUSH_MATCH_CACHE_POINT.
  sig [Ptr, Word, Word] => Void
  def zr_onig_push_cache_point(m, index, mask)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_MATCH_CACHE_POINT)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, index)
    OnigStk.set_b(stk, mask)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # CHECK_MATCH_CACHE at the opcode `pbegin`, with the match at
  # OnigMatch.s. Returns 0 to continue (after it pushes a cache point, if
  # there is one), 1 to fail, or 2 to continue at the look-around's match
  # address, which is in OnigMatch.p.
  sig [Ptr, Ptr] => Word
  def zr_onig_check_match_cache(m, pbegin)
    return 0 if OnigMatch.match_cache_status(m) != ONIG_MATCH_CACHE_STATUS_ENABLED
    cop = Machine.slot(8)
    Machine.store64(cop, 0, 0)
    cache_point = zr_onig_find_cache_point(m, pbegin, cop)
    return 0 if cache_point < 0
    point = (OnigMatch.num_cache_points(m) * Machine.word(OnigMatch.s(m) - OnigMatch.str(m))) + cache_point
    index = point >> 3
    mask = 1 << (point & 7)
    buf = OnigMatch.match_cache_buf(m)
    if (Machine.word(Machine.load8(buf + index, 0)) & mask) != 0
      row = Machine.ptr(Machine.load64(cop, 0))
      nesting = OnigCacheOp.lookaround_nesting(row)
      return 1 if nesting == 0
      if nesting < 0
        if zr_onig_check_extended_cache_point(buf, index, mask)
          zr_onig_stack_stop_bt_fail(m)
        end
        return 1
      end
      if zr_onig_check_extended_cache_point(buf, index, mask)
        OnigMatch.set_p(m, OnigCacheOp.match_addr(row))
        return 2
      end
      return 1
    end
    zr_onig_push_cache_point(m, index, mask)
    0
  end

  # The fail path accounting (OP_FAIL, regexec.c:4103-4160). It adds
  # one to the failure count. When the failures get to the subject length
  # times the count, it counts and numbers the cache opcodes and makes the
  # bit array. Returns 0, or an error.
  sig [Ptr] => Word
  def zr_onig_fail_match_cache(m)
    status = OnigMatch.match_cache_status(m)
    return 0 if status == ONIG_MATCH_CACHE_STATUS_DISABLED
    num_fails = OnigMatch.num_fails(m) + 1
    OnigMatch.set_num_fails(m, num_fails)
    len = Machine.word(OnigMatch.aend(m) - OnigMatch.str(m))
    return 0 if num_fails < len * OnigMatch.num_cache_opcodes(m)
    if status == ONIG_MATCH_CACHE_STATUS_UNINIT
      OnigMatch.set_match_cache_status(m, ONIG_MATCH_CACHE_STATUS_INIT)
      cell = Machine.slot(8)
      r = zr_onig_count_num_cache_opcodes(m, cell)
      return r if r < 0
      OnigMatch.set_num_cache_opcodes(m, Machine.load64(cell, 0))
    end
    n = OnigMatch.num_cache_opcodes(m)
    if n == ONIG_NUM_CACHE_OPCODES_IMPOSSIBLE || n == 0
      OnigMatch.set_match_cache_status(m, ONIG_MATCH_CACHE_STATUS_DISABLED)
      return 0
    end
    return 0 if num_fails < len * n
    if OnigMatch.cache_opcodes(m) == 0
      OnigMatch.set_match_cache_status(m, ONIG_MATCH_CACHE_STATUS_ENABLED)
      rows = Libc.malloc(n * OnigCacheOp.size)
      return ONIGERR_MEMORY if rows == 0
      cell = Machine.slot(8)
      r = zr_onig_init_cache_rows(m, rows, cell)
      if r < 0
        Libc.free(rows)
        return r
      end
      OnigMatch.set_num_cache_points(m, Machine.load64(cell, 0))
      OnigMatch.set_cache_opcodes(m, rows)
    end
    if OnigMatch.match_cache_buf(m) == 0
      length = len + 1
      points = OnigMatch.num_cache_points(m) * length
      # Overflow check
      return ONIGERR_MEMORY if points / length != OnigMatch.num_cache_points(m)
      return ONIGERR_MEMORY if points >= ONIG_LONG_MAX_LIMIT
      buf_len = (points >> 3) + ((points & 7) != 0 ? 1 : 0) + 1
      buf = Libc.malloc(buf_len)
      return ONIGERR_MEMORY if buf == 0
      Libc.memset(buf, Machine.i32(0), buf_len)
      OnigMatch.set_match_cache_buf(m, buf)
    end
    0
  end
end
