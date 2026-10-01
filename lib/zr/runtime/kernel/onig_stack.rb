module Zr::Kern
  # Onigmo's backtrack stack (regexec.c:1043-1830): the entry type, the
  # STACK_* macros as defs on the match state, and the stack itself. The
  # stack starts in the search's arena and doubles into the heap. Derived
  # from Onigmo; the license is in lib/zr/runtime/kernel/regexp.rb.
  Libc.import :malloc, [Word] => Ptr
  Libc.import :free, [Ptr] => Void
  Libc.import :memmove, [Ptr, Ptr, Word] => Ptr
  Libc.import :abort, [] => Void

  STK_ALT = 1
  STK_LOOK_BEHIND_NOT = 2
  STK_POS_NOT = 3
  STK_MEM_START = 256
  STK_MEM_END = 33280
  STK_REPEAT_INC = 768
  STK_NULL_CHECK_START = 12288
  STK_NULL_CHECK_END = 20480
  STK_MEM_END_MARK = 33792
  STK_POS = 1280
  STK_STOP_BT = 1536
  STK_REPEAT = 1792
  STK_CALL_FRAME = 2048
  STK_RETURN = 2304
  STK_VOID = 2560
  STK_ABSENT_POS = 2816
  STK_ABSENT = 3072
  STK_MASK_POP_USED = 255
  STK_MASK_TO_VOID_TARGET = 4351
  STK_MASK_MEM_END_OR_MARK = 32768
  ONIG_INVALID_STACK_INDEX = 0 - 1
  ONIG_INIT_MATCH_STACK_SIZE = 160
  ONIG_STACK_POP_LEVEL_FREE = 0
  ONIG_STACK_POP_LEVEL_MEM_START = 1
  ONIG_STACK_POP_LEVEL_ALL = 2

  # One stack entry (OnigStackType). The fields a-d have a different
  # meaning for each role of the C union:
  #   state:      a pcode, b pstr, c pstr_prev, d pkeep
  #   repeat:     a count, b pcode, c num
  #   repeat_inc: a si
  #   mem:        a num, b pstr, c start, d end
  #   null_check: a num, b pstr
  #   call_frame: a ret_addr
  #   absent_pos: a abs_pstr, b end_pstr
  OnigStk = layout type: Word, null_check: Word, a: Word, b: Word, c: Word, d: Word

  # The match in progress: OnigMatchArg, plus the match_at locals that
  # the opcode defs share. `mem_start_stk` and `mem_end_stk` each contain
  # num_mem + 1 words, with group 0 (ADD_NUMMEM under USE_SUBEXP_CALL).
  # `aend` is match_at's `end`, which the absent operators change.
  OnigMatch = layout prog: Ptr, code: Ptr, enc: Word, options: Word, case_fold: Word,
    num_mem: Word, pop_level: Word, bt_mem_start: Word, bt_mem_end: Word,
    str: Ptr, text_end: Ptr, sstart: Ptr, gpos: Ptr, region: Ptr, mopts: Word,
    stk_base: Ptr, stk_end: Ptr, stk: Ptr, stk_alloc: Ptr, stack_p: Ptr, stack_n: Word,
    repeat_stk: Ptr, mem_start_stk: Ptr, mem_end_stk: Ptr,
    counter: Word, end_time: Word, limit: Word,
    p: Ptr, s: Ptr, sprev: Ptr, pkeep: Ptr, aend: Ptr, best_len: Word,
    match_cache_status: Word, num_fails: Word, num_cache_opcodes: Word, cache_opcodes: Ptr,
    num_cache_points: Word, match_cache_buf: Ptr

  sig [Ptr, Word] => Ptr
  def zr_onig_stk_at(m, index)
    OnigMatch.stk_base(m) + (index * OnigStk.size)
  end

  sig [Ptr, Ptr] => Word
  def zr_onig_stk_index(m, stk)
    Machine.word((stk - OnigMatch.stk_base(m)) / OnigStk.size)
  end

  sig [Ptr, Word] => Word
  def zr_onig_mem_start(m, n)
    Machine.load64(OnigMatch.mem_start_stk(m) + (n * 8), 0)
  end

  sig [Ptr, Word, Word] => Void
  def zr_onig_set_mem_start(m, n, v)
    Machine.store64(OnigMatch.mem_start_stk(m) + (n * 8), 0, v)
  end

  sig [Ptr, Word] => Word
  def zr_onig_mem_end(m, n)
    Machine.load64(OnigMatch.mem_end_stk(m) + (n * 8), 0)
  end

  sig [Ptr, Word, Word] => Void
  def zr_onig_set_mem_end(m, n, v)
    Machine.store64(OnigMatch.mem_end_stk(m) + (n * 8), 0, v)
  end

  # BIT_STATUS_AT: the bit of group n. Groups after 31 share bit 0.
  sig [Word, Word] => Bool
  def zr_onig_bit_status_at(stats, n)
    n < 32 ? (stats & (1 << n)) != 0 : (stats & 1) != 0
  end

  # The start pointer of group `mem`. The stored value is a stack index
  # when the group backtracks its start, and the pointer if not.
  sig [Ptr, Word] => Ptr
  def zr_onig_mem_start_ptr(m, mem)
    v = zr_onig_mem_start(m, mem)
    if zr_onig_bit_status_at(OnigMatch.bt_mem_start(m), mem)
      return Machine.ptr(OnigStk.b(zr_onig_stk_at(m, v)))
    end
    Machine.ptr(v)
  end

  sig [Ptr, Word] => Ptr
  def zr_onig_mem_end_ptr(m, mem)
    v = zr_onig_mem_end(m, mem)
    if zr_onig_bit_status_at(OnigMatch.bt_mem_end(m), mem)
      return Machine.ptr(OnigStk.b(zr_onig_stk_at(m, v)))
    end
    Machine.ptr(v)
  end

  # stack_double: doubles the stack size. The first time, it copies out of
  # the arena. After that, it copies out of the smaller heap block and
  # frees it. This does the work of realloc, because a wasm module's
  # allocator has no realloc.
  sig [Ptr] => Void
  def zr_onig_stack_double(m)
    base = OnigMatch.stk_base(m)
    n = Machine.word((OnigMatch.stk_end(m) - base) / OnigStk.size)
    x = Libc.malloc(OnigStk.size * n * 2)
    Libc.abort() if x == 0
    Libc.memmove(x, base, n * OnigStk.size)
    if base != OnigMatch.stk_alloc(m) || OnigMatch.stack_p(m) != 0
      Libc.free(base)
    end
    n = n * 2
    OnigMatch.set_stk(m, x + (OnigMatch.stk(m) - base))
    OnigMatch.set_stk_base(m, x)
    OnigMatch.set_stk_end(m, x + (n * OnigStk.size))
  end

  # STACK_ENSURE(1).
  sig [Ptr] => Void
  def zr_onig_stack_ensure(m)
    if OnigMatch.stk_end(m) - OnigMatch.stk(m) < OnigStk.size
      zr_onig_stack_double(m)
    end
  end

  # STACK_SAVE: a stack that moved out of the arena stays with the search.
  sig [Ptr] => Void
  def zr_onig_stack_save(m)
    if OnigMatch.stk_base(m) != OnigMatch.stk_alloc(m)
      OnigMatch.set_stack_p(m, OnigMatch.stk_base(m))
      OnigMatch.set_stack_n(m, Machine.word((OnigMatch.stk_end(m) - OnigMatch.stk_base(m)) / OnigStk.size))
    end
  end

  # Returns the null_check for a new entry: the null_check of the entry
  # below it, or 0 at the base.
  sig [Ptr, Ptr] => Word
  def zr_onig_inherit_null_check(m, stk)
    stk == OnigMatch.stk_base(m) ? 0 : OnigStk.null_check(stk - OnigStk.size)
  end

  # STACK_PUSH: a state entry (ALT, POS, POS_NOT, LOOK_BEHIND_NOT).
  sig [Ptr, Word, Ptr, Ptr, Ptr, Ptr] => Void
  def zr_onig_push(m, type, pat, s, sprev, keep)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, type)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, Machine.word(pat))
    OnigStk.set_b(stk, Machine.word(s))
    OnigStk.set_c(stk, Machine.word(sprev))
    OnigStk.set_d(stk, Machine.word(keep))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_TYPE: a marker entry (STOP_BT, ABSENT, RETURN).
  sig [Ptr, Word] => Void
  def zr_onig_push_type(m, type)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, type)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_REPEAT.
  sig [Ptr, Word, Ptr] => Void
  def zr_onig_push_repeat(m, id, pat)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_REPEAT)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_c(stk, id)
    OnigStk.set_b(stk, Machine.word(pat))
    OnigStk.set_a(stk, 0)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_REPEAT_INC.
  sig [Ptr, Word] => Void
  def zr_onig_push_repeat_inc(m, sindex)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_REPEAT_INC)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, sindex)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_MEM_START.
  sig [Ptr, Word, Ptr] => Void
  def zr_onig_push_mem_start(m, mnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_MEM_START)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, mnum)
    OnigStk.set_b(stk, Machine.word(s))
    OnigStk.set_c(stk, zr_onig_mem_start(m, mnum))
    OnigStk.set_d(stk, zr_onig_mem_end(m, mnum))
    zr_onig_set_mem_start(m, mnum, zr_onig_stk_index(m, stk))
    zr_onig_set_mem_end(m, mnum, ONIG_INVALID_STACK_INDEX)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_MEM_END.
  sig [Ptr, Word, Ptr] => Void
  def zr_onig_push_mem_end(m, mnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_MEM_END)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, mnum)
    OnigStk.set_b(stk, Machine.word(s))
    OnigStk.set_c(stk, zr_onig_mem_start(m, mnum))
    OnigStk.set_d(stk, zr_onig_mem_end(m, mnum))
    zr_onig_set_mem_end(m, mnum, zr_onig_stk_index(m, stk))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_MEM_END_MARK.
  sig [Ptr, Word] => Void
  def zr_onig_push_mem_end_mark(m, mnum)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_MEM_END_MARK)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, mnum)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_NULL_CHECK_START: its null_check is its own index.
  sig [Ptr, Word, Ptr] => Void
  def zr_onig_push_null_check_start(m, cnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_NULL_CHECK_START)
    OnigStk.set_null_check(stk, zr_onig_stk_index(m, stk))
    OnigStk.set_a(stk, cnum)
    OnigStk.set_b(stk, Machine.word(s))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_NULL_CHECK_END.
  sig [Ptr, Word] => Void
  def zr_onig_push_null_check_end(m, cnum)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_NULL_CHECK_END)
    OnigStk.set_null_check(stk, zr_onig_stk_index(m, stk))
    OnigStk.set_a(stk, cnum)
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_CALL_FRAME.
  sig [Ptr, Ptr] => Void
  def zr_onig_push_call_frame(m, pat)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_CALL_FRAME)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, Machine.word(pat))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # STACK_PUSH_ABSENT_POS.
  sig [Ptr, Ptr, Ptr] => Void
  def zr_onig_push_absent_pos(m, start, e)
    zr_onig_stack_ensure(m)
    stk = OnigMatch.stk(m)
    OnigStk.set_type(stk, STK_ABSENT_POS)
    OnigStk.set_null_check(stk, zr_onig_inherit_null_check(m, stk))
    OnigStk.set_a(stk, Machine.word(start))
    OnigStk.set_b(stk, Machine.word(e))
    OnigMatch.set_stk(m, stk + OnigStk.size)
  end

  # Restores the group positions when the stack pops a MEM_START or
  # MEM_END entry.
  sig [Ptr, Ptr] => Void
  def zr_onig_restore_mem(m, stk)
    num = OnigStk.a(stk)
    zr_onig_set_mem_start(m, num, OnigStk.c(stk))
    zr_onig_set_mem_end(m, num, OnigStk.d(stk))
  end

  # Undoes the count that a REPEAT_INC entry added, when the stack pops
  # it.
  sig [Ptr, Ptr] => Void
  def zr_onig_undo_repeat_inc(m, stk)
    rep = zr_onig_stk_at(m, OnigStk.a(stk))
    OnigStk.set_a(rep, OnigStk.a(rep) - 1)
  end

  # STACK_POP at the pattern's pop level. The stack pointer stops on the
  # state entry from which the match continues.
  sig [Ptr] => Void
  def zr_onig_stack_pop(m)
    level = OnigMatch.pop_level(m)
    stk = OnigMatch.stk(m)
    while true
      stk = stk - OnigStk.size
      type = OnigStk.type(stk)
      if (type & STK_MASK_POP_USED) != 0
        break
      end
      if level != ONIG_STACK_POP_LEVEL_FREE
        if type == STK_MEM_START
          zr_onig_restore_mem(m, stk)
        elsif level == ONIG_STACK_POP_LEVEL_ALL
          if type == STK_REPEAT_INC
            zr_onig_undo_repeat_inc(m, stk)
          elsif type == STK_MEM_END
            zr_onig_restore_mem(m, stk)
          end
        end
      end
      zr_onig_memoize_cache_point(m, stk)
    end
    OnigMatch.set_stk(m, stk)
  end

  # STACK_POP_TIL_POS_NOT, STACK_POP_TIL_LOOK_BEHIND_NOT and
  # STACK_POP_TIL_ABSENT: pop down to the entry of `stop`, and undo the
  # entries above it. For a negative look-ahead, each dropped backtrack
  # target counts as a failure, and its cache points are memoized.
  sig [Ptr, Word] => Void
  def zr_onig_stack_pop_til(m, stop)
    stk = OnigMatch.stk(m)
    while true
      stk = stk - OnigStk.size
      type = OnigStk.type(stk)
      if type == stop
        break
      end
      if type == STK_MEM_START
        zr_onig_restore_mem(m, stk)
      elsif type == STK_REPEAT_INC
        zr_onig_undo_repeat_inc(m, stk)
      elsif type == STK_MEM_END
        zr_onig_restore_mem(m, stk)
      elsif stop == STK_POS_NOT && (type & STK_MASK_TO_VOID_TARGET) != 0
        OnigMatch.set_num_fails(m, OnigMatch.num_fails(m) + 1)
      end
      if stop == STK_POS_NOT
        zr_onig_memoize_lookaround_cache_point(m, stk)
      end
    end
    OnigMatch.set_stk(m, stk)
  end

  # STACK_POS_END and STACK_STOP_BT_END: void every backtrack target above
  # the nearest entry of `mark`, and the mark itself. Returns that entry.
  # Each voided target counts as a failure for the match cache. The cache
  # points of a look-ahead are memoized, and the cache points of an atomic
  # group become atomic cache points.
  sig [Ptr, Word] => Ptr
  def zr_onig_stack_void_til(m, mark)
    k = OnigMatch.stk(m)
    while true
      k = k - OnigStk.size
      type = OnigStk.type(k)
      if (type & STK_MASK_TO_VOID_TARGET) != 0
        OnigMatch.set_num_fails(m, OnigMatch.num_fails(m) + 1)
        OnigStk.set_type(k, STK_VOID)
      elsif type == mark
        OnigStk.set_type(k, STK_VOID)
        break
      elsif mark == STK_POS
        zr_onig_memoize_lookaround_cache_point(m, k)
      elsif type == STK_MATCH_CACHE_POINT
        OnigStk.set_type(k, STK_ATOMIC_MATCH_CACHE_POINT)
      end
    end
    k
  end

  # STACK_NULL_CHECK: whether the loop `id` is at its start position. It
  # reads the NULL_CHECK_START entry that the top entry's null_check
  # refers to.
  sig [Ptr, Word, Ptr] => Bool
  def zr_onig_null_check(m, id, s)
    k = zr_onig_stk_at(m, OnigStk.null_check(OnigMatch.stk(m) - OnigStk.size)) + OnigStk.size
    while true
      k = k - OnigStk.size
      if OnigStk.type(k) == STK_NULL_CHECK_START && OnigStk.a(k) == id
        return Machine.ptr(OnigStk.b(k)) == s
      end
    end
    false
  end

  # The MEMST part of STACK_NULL_CHECK_MEMST(_REC). It scans from the
  # START entry `k` up to the top. Returns 1 when every group is empty and
  # did not move, -1 when every group is empty but moved, and 0 when a
  # group captured text.
  sig [Ptr, Ptr, Ptr] => Word
  def zr_onig_null_check_memst_scan(m, k, s)
    isnull = 1
    top = OnigMatch.stk(m)
    while k < top
      if OnigStk.type(k) == STK_MEM_START
        if OnigStk.d(k) == ONIG_INVALID_STACK_INDEX
          return 0
        end
        if zr_onig_bit_status_at(OnigMatch.bt_mem_end(m), OnigStk.a(k))
          endp = Machine.ptr(OnigStk.b(zr_onig_stk_at(m, OnigStk.d(k))))
        else
          endp = Machine.ptr(OnigStk.d(k))
        end
        if Machine.ptr(OnigStk.b(zr_onig_stk_at(m, OnigStk.c(k)))) != endp
          return 0
        end
        if endp != s
          isnull = 0 - 1
        end
      end
      k = k + OnigStk.size
    end
    isnull
  end

  # STACK_NULL_CHECK_MEMST.
  sig [Ptr, Word, Ptr] => Word
  def zr_onig_null_check_memst(m, id, s)
    k = zr_onig_stk_at(m, OnigStk.null_check(OnigMatch.stk(m) - OnigStk.size)) + OnigStk.size
    while true
      k = k - OnigStk.size
      if OnigStk.type(k) == STK_NULL_CHECK_START && OnigStk.a(k) == id
        if Machine.ptr(OnigStk.b(k)) != s
          return 0
        end
        return zr_onig_null_check_memst_scan(m, k, s)
      end
    end
    0
  end

  # STACK_NULL_CHECK_MEMST_REC: the same across subexpression calls. It
  # finds the START entry by nesting level.
  sig [Ptr, Word, Ptr] => Word
  def zr_onig_null_check_memst_rec(m, id, s)
    level = 0
    k = zr_onig_stk_at(m, OnigStk.null_check(OnigMatch.stk(m) - OnigStk.size)) + OnigStk.size
    while true
      k = k - OnigStk.size
      type = OnigStk.type(k)
      if type == STK_NULL_CHECK_START
        if OnigStk.a(k) == id
          if level == 0
            if Machine.ptr(OnigStk.b(k)) != s
              return 0
            end
            return zr_onig_null_check_memst_scan(m, k, s)
          end
          level -= 1
        end
      elsif type == STK_NULL_CHECK_END
        if OnigStk.a(k) == id
          level += 1
        end
      end
    end
    0
  end

  # STACK_GET_REPEAT: returns the REPEAT entry of `id` at this call level.
  sig [Ptr, Word] => Ptr
  def zr_onig_get_repeat(m, id)
    level = 0
    k = OnigMatch.stk(m)
    while true
      k = k - OnigStk.size
      type = OnigStk.type(k)
      if type == STK_REPEAT
        if level == 0 && OnigStk.c(k) == id
          break
        end
      elsif type == STK_CALL_FRAME
        level -= 1
      elsif type == STK_RETURN
        level += 1
      end
    end
    k
  end

  # STACK_RETURN: returns the return address of the innermost open call
  # frame.
  sig [Ptr] => Ptr
  def zr_onig_stack_return(m)
    level = 0
    k = OnigMatch.stk(m)
    while true
      k = k - OnigStk.size
      type = OnigStk.type(k)
      if type == STK_CALL_FRAME
        if level == 0
          return Machine.ptr(OnigStk.a(k))
        end
        level -= 1
      elsif type == STK_RETURN
        level += 1
      end
    end
    Machine.ptr(0)
  end

  # STACK_GET_MEM_START: returns the MEM_START entry of `mnum` that no
  # MEM_END entry near the top has closed.
  sig [Ptr, Word] => Ptr
  def zr_onig_get_mem_start(m, mnum)
    level = 0
    k = OnigMatch.stk(m)
    base = OnigMatch.stk_base(m)
    while k > base
      k = k - OnigStk.size
      type = OnigStk.type(k)
      if (type & STK_MASK_MEM_END_OR_MARK) != 0 && OnigStk.a(k) == mnum
        level += 1
      elsif type == STK_MEM_START && OnigStk.a(k) == mnum
        if level == 0
          break
        end
        level -= 1
      end
    end
    k
  end

  # mem_is_in_memp: whether `mem` is one of the `num` MemNums at memp.
  sig [Word, Word, Ptr] => Bool
  def zr_onig_mem_in_memp(mem, num, memp)
    i = 0
    while i < num
      if mem == zr_onig_get_memnum(memp + (i * 2))
        return true
      end
      i += 1
    end
    false
  end

  # Reads a MemNum operand: two little-endian bytes.
  sig [Ptr] => Word
  def zr_onig_get_memnum(p)
    Machine.word(Machine.load8(p, 0)) | (Machine.word(Machine.load8(p, 1)) << 8)
  end

  # backref_match_at_nested_level: matches the text at the pointer in the
  # word `ps` against the capture of one of the groups at memp, made
  # `nest` call levels up. Returns whether it matched. On a match, it
  # moves the pointer in `ps` past the match.
  sig [Ptr, Word, Word, Word, Ptr, Ptr, Ptr] => Bool
  def zr_onig_backref_at_nested_level(m, ignore_case, nest, mem_num, memp, ps, send)
    pend = Machine.ptr(0)
    level = 0
    k = OnigMatch.stk(m) - OnigStk.size
    base = OnigMatch.stk_base(m)
    while k >= base
      type = OnigStk.type(k)
      if type == STK_CALL_FRAME
        level -= 1
      elsif type == STK_RETURN
        level += 1
      elsif level == nest
        if type == STK_MEM_START
          if zr_onig_mem_in_memp(OnigStk.a(k), mem_num, memp)
            pstart = Machine.ptr(OnigStk.b(k))
            if pend != 0
              s = Machine.ptr(Machine.load64(ps, 0))
              return false if pend - pstart > send - s
              if ignore_case != 0
                ss = zr_onig_string_cmp_ic(OnigMatch.enc(m), OnigMatch.case_fold(m), pstart, s, Machine.word(pend - pstart), send)
                return false if ss == 0
              else
                p = pstart
                ss = s
                while p < pend
                  return false if Machine.load8(p, 0) != Machine.load8(ss, 0)
                  p = p + 1
                  ss = ss + 1
                end
              end
              Machine.store64(ps, 0, Machine.word(ss))
              return true
            end
          end
        elsif type == STK_MEM_END
          if zr_onig_mem_in_memp(OnigStk.a(k), mem_num, memp)
            pend = Machine.ptr(OnigStk.b(k))
          end
        end
      end
      k = k - OnigStk.size
    end
    false
  end
end
