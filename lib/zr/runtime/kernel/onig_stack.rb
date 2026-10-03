module Zr::Kern
  # Onigmo's backtrack stack (regexec.c:1043-1830): the entry type, the
  # STACK_* macros as defs on the match state, and the stack itself. The
  # stack starts in the search's arena and doubles into the heap. Derived
  # from Onigmo; the license is in lib/zr/runtime/kernel/regexp.rb.

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
  class OnigStk < Layout
    attr_accessor :type #: word
    attr_accessor :null_check #: word
    attr_accessor :a #: word
    attr_accessor :b #: word
    attr_accessor :c #: word
    attr_accessor :d #: word
  end

  # The match in progress: OnigMatchArg, plus the match_at locals that
  # the opcode defs share. `mem_start_stk` and `mem_end_stk` each contain
  # num_mem + 1 words, with group 0 (ADD_NUMMEM under USE_SUBEXP_CALL).
  # `aend` is match_at's `end`, which the absent operators change.
  class OnigMatch < Layout
    attr_accessor :prog #: ptr
    attr_accessor :code #: ptr
    attr_accessor :enc #: word
    attr_accessor :options #: word
    attr_accessor :case_fold #: word
    attr_accessor :num_mem #: word
    attr_accessor :pop_level #: word
    attr_accessor :bt_mem_start #: word
    attr_accessor :bt_mem_end #: word
    attr_accessor :str #: ptr
    attr_accessor :text_end #: ptr
    attr_accessor :sstart #: ptr
    attr_accessor :gpos #: ptr
    attr_accessor :region #: ptr
    attr_accessor :mopts #: word
    attr_accessor :stk_base #: ptr
    attr_accessor :stk_end #: ptr
    attr_accessor :stk #: ptr
    attr_accessor :stk_alloc #: ptr
    attr_accessor :stack_p #: ptr
    attr_accessor :stack_n #: word
    attr_accessor :repeat_stk #: ptr
    attr_accessor :mem_start_stk #: ptr
    attr_accessor :mem_end_stk #: ptr
    attr_accessor :counter #: word
    attr_accessor :end_time #: word
    attr_accessor :limit #: word
    attr_accessor :p #: ptr
    attr_accessor :s #: ptr
    attr_accessor :sprev #: ptr
    attr_accessor :pkeep #: ptr
    attr_accessor :aend #: ptr
    attr_accessor :best_len #: word
    attr_accessor :match_cache_status #: word
    attr_accessor :num_fails #: word
    attr_accessor :num_cache_opcodes #: word
    attr_accessor :cache_opcodes #: ptr
    attr_accessor :num_cache_points #: word
    attr_accessor :match_cache_buf #: ptr
  end

  #: (ptr, word) -> ptr
  def zr_onig_stk_at(m, index)
    OnigMatch[m].stk_base + (index * OnigStk.size)
  end

  #: (ptr, ptr) -> word
  def zr_onig_stk_index(m, stk)
    Machine.word((stk - OnigMatch[m].stk_base) / OnigStk.size)
  end

  #: (ptr, word) -> word
  def zr_onig_mem_start(m, n)
    Machine.load64(OnigMatch[m].mem_start_stk + (n * 8), 0)
  end

  #: (ptr, word, word) -> void
  def zr_onig_set_mem_start(m, n, v)
    Machine.store64(OnigMatch[m].mem_start_stk + (n * 8), 0, v)
  end

  #: (ptr, word) -> word
  def zr_onig_mem_end(m, n)
    Machine.load64(OnigMatch[m].mem_end_stk + (n * 8), 0)
  end

  #: (ptr, word, word) -> void
  def zr_onig_set_mem_end(m, n, v)
    Machine.store64(OnigMatch[m].mem_end_stk + (n * 8), 0, v)
  end

  # BIT_STATUS_AT: the bit of group n. Groups after 31 share bit 0.
  #: (word, word) -> bool
  def zr_onig_bit_status_at(stats, n)
    n < 32 ? (stats & (1 << n)) != 0 : (stats & 1) != 0
  end

  # The start pointer of group `mem`. The stored value is a stack index
  # when the group backtracks its start, and the pointer if not.
  #: (ptr, word) -> ptr
  def zr_onig_mem_start_ptr(m, mem)
    v = zr_onig_mem_start(m, mem)
    if zr_onig_bit_status_at(OnigMatch[m].bt_mem_start, mem)
      return Machine.ptr(OnigStk[zr_onig_stk_at(m, v)].b)
    end
    Machine.ptr(v)
  end

  #: (ptr, word) -> ptr
  def zr_onig_mem_end_ptr(m, mem)
    v = zr_onig_mem_end(m, mem)
    if zr_onig_bit_status_at(OnigMatch[m].bt_mem_end, mem)
      return Machine.ptr(OnigStk[zr_onig_stk_at(m, v)].b)
    end
    Machine.ptr(v)
  end

  # stack_double: doubles the stack size. The first time, it copies out of
  # the arena. After that, it copies out of the smaller heap block and
  # frees it. This does the work of realloc, because a wasm module's
  # allocator has no realloc.
  #: (ptr) -> void
  def zr_onig_stack_double(m)
    base = OnigMatch[m].stk_base
    n = Machine.word((OnigMatch[m].stk_end - base) / OnigStk.size)
    x = Libc.malloc(OnigStk.size * n * 2)
    Libc.abort() if x == 0
    Libc.memmove(x, base, n * OnigStk.size)
    if base != OnigMatch[m].stk_alloc || OnigMatch[m].stack_p != 0
      Libc.free(base)
    end
    n = n * 2
    OnigMatch[m].stk = x + (OnigMatch[m].stk - base)
    OnigMatch[m].stk_base = x
    OnigMatch[m].stk_end = x + (n * OnigStk.size)
  end

  # STACK_ENSURE(1).
  #: (ptr) -> void
  def zr_onig_stack_ensure(m)
    if OnigMatch[m].stk_end - OnigMatch[m].stk < OnigStk.size
      zr_onig_stack_double(m)
    end
  end
  # Each push of the match loop runs these, so they are in its code.
  inline :zr_onig_stack_ensure

  # STACK_SAVE: a stack that moved out of the arena stays with the search.
  #: (ptr) -> void
  def zr_onig_stack_save(m)
    if OnigMatch[m].stk_base != OnigMatch[m].stk_alloc
      OnigMatch[m].stack_p = OnigMatch[m].stk_base
      OnigMatch[m].stack_n = Machine.word((OnigMatch[m].stk_end - OnigMatch[m].stk_base) / OnigStk.size)
    end
  end

  # Returns the null_check for a new entry: the null_check of the entry
  # below it, or 0 at the base.
  #: (ptr, ptr) -> word
  def zr_onig_inherit_null_check(m, stk)
    stk == OnigMatch[m].stk_base ? 0 : OnigStk[stk - OnigStk.size].null_check
  end

  inline :zr_onig_inherit_null_check

  # STACK_PUSH: a state entry (ALT, POS, POS_NOT, LOOK_BEHIND_NOT).
  #: (ptr, word, ptr, ptr, ptr, ptr) -> void
  def zr_onig_push(m, type, pat, s, sprev, keep)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = type
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = Machine.word(pat)
    OnigStk[stk].b = Machine.word(s)
    OnigStk[stk].c = Machine.word(sprev)
    OnigStk[stk].d = Machine.word(keep)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  inline :zr_onig_push

  # STACK_PUSH_TYPE: a marker entry (STOP_BT, ABSENT, RETURN).
  #: (ptr, word) -> void
  def zr_onig_push_type(m, type)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = type
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_REPEAT.
  #: (ptr, word, ptr) -> void
  def zr_onig_push_repeat(m, id, pat)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_REPEAT
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].c = id
    OnigStk[stk].b = Machine.word(pat)
    OnigStk[stk].a = 0
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_REPEAT_INC.
  #: (ptr, word) -> void
  def zr_onig_push_repeat_inc(m, sindex)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_REPEAT_INC
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = sindex
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_MEM_START.
  #: (ptr, word, ptr) -> void
  def zr_onig_push_mem_start(m, mnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_MEM_START
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = mnum
    OnigStk[stk].b = Machine.word(s)
    OnigStk[stk].c = zr_onig_mem_start(m, mnum)
    OnigStk[stk].d = zr_onig_mem_end(m, mnum)
    zr_onig_set_mem_start(m, mnum, zr_onig_stk_index(m, stk))
    zr_onig_set_mem_end(m, mnum, ONIG_INVALID_STACK_INDEX)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_MEM_END.
  #: (ptr, word, ptr) -> void
  def zr_onig_push_mem_end(m, mnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_MEM_END
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = mnum
    OnigStk[stk].b = Machine.word(s)
    OnigStk[stk].c = zr_onig_mem_start(m, mnum)
    OnigStk[stk].d = zr_onig_mem_end(m, mnum)
    zr_onig_set_mem_end(m, mnum, zr_onig_stk_index(m, stk))
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_MEM_END_MARK.
  #: (ptr, word) -> void
  def zr_onig_push_mem_end_mark(m, mnum)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_MEM_END_MARK
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = mnum
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_NULL_CHECK_START: its null_check is its own index.
  #: (ptr, word, ptr) -> void
  def zr_onig_push_null_check_start(m, cnum, s)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_NULL_CHECK_START
    OnigStk[stk].null_check = zr_onig_stk_index(m, stk)
    OnigStk[stk].a = cnum
    OnigStk[stk].b = Machine.word(s)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_NULL_CHECK_END.
  #: (ptr, word) -> void
  def zr_onig_push_null_check_end(m, cnum)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_NULL_CHECK_END
    OnigStk[stk].null_check = zr_onig_stk_index(m, stk)
    OnigStk[stk].a = cnum
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_CALL_FRAME.
  #: (ptr, ptr) -> void
  def zr_onig_push_call_frame(m, pat)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_CALL_FRAME
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = Machine.word(pat)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # STACK_PUSH_ABSENT_POS.
  #: (ptr, ptr, ptr) -> void
  def zr_onig_push_absent_pos(m, start, e)
    zr_onig_stack_ensure(m)
    stk = OnigMatch[m].stk
    OnigStk[stk].type = STK_ABSENT_POS
    OnigStk[stk].null_check = zr_onig_inherit_null_check(m, stk)
    OnigStk[stk].a = Machine.word(start)
    OnigStk[stk].b = Machine.word(e)
    OnigMatch[m].stk = stk + OnigStk.size
  end

  # Restores the group positions when the stack pops a MEM_START or
  # MEM_END entry.
  #: (ptr, ptr) -> void
  def zr_onig_restore_mem(m, stk)
    num = OnigStk[stk].a
    zr_onig_set_mem_start(m, num, OnigStk[stk].c)
    zr_onig_set_mem_end(m, num, OnigStk[stk].d)
  end

  # Undoes the count that a REPEAT_INC entry added, when the stack pops
  # it.
  #: (ptr, ptr) -> void
  def zr_onig_undo_repeat_inc(m, stk)
    rep = zr_onig_stk_at(m, OnigStk[stk].a)
    OnigStk[rep].a = OnigStk[rep].a - 1
  end

  # STACK_POP at the pattern's pop level. The stack pointer stops on the
  # state entry from which the match continues.
  #: (ptr) -> void
  def zr_onig_stack_pop(m)
    level = OnigMatch[m].pop_level
    stk = OnigMatch[m].stk
    while true
      stk = stk - OnigStk.size
      type = OnigStk[stk].type
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
    OnigMatch[m].stk = stk
  end

  # STACK_POP_TIL_POS_NOT, STACK_POP_TIL_LOOK_BEHIND_NOT and
  # STACK_POP_TIL_ABSENT: pop down to the entry of `stop`, and undo the
  # entries above it. For a negative look-ahead, each dropped backtrack
  # target counts as a failure, and its cache points are memoized.
  #: (ptr, word) -> void
  def zr_onig_stack_pop_til(m, stop)
    stk = OnigMatch[m].stk
    while true
      stk = stk - OnigStk.size
      type = OnigStk[stk].type
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
        OnigMatch[m].num_fails = OnigMatch[m].num_fails + 1
      end
      if stop == STK_POS_NOT
        zr_onig_memoize_lookaround_cache_point(m, stk)
      end
    end
    OnigMatch[m].stk = stk
  end

  # STACK_POS_END and STACK_STOP_BT_END: void every backtrack target above
  # the nearest entry of `mark`, and the mark itself. Returns that entry.
  # Each voided target counts as a failure for the match cache. The cache
  # points of a look-ahead are memoized, and the cache points of an atomic
  # group become atomic cache points.
  #: (ptr, word) -> ptr
  def zr_onig_stack_void_til(m, mark)
    k = OnigMatch[m].stk
    while true
      k = k - OnigStk.size
      type = OnigStk[k].type
      if (type & STK_MASK_TO_VOID_TARGET) != 0
        OnigMatch[m].num_fails = OnigMatch[m].num_fails + 1
        OnigStk[k].type = STK_VOID
      elsif type == mark
        OnigStk[k].type = STK_VOID
        break
      elsif mark == STK_POS
        zr_onig_memoize_lookaround_cache_point(m, k)
      elsif type == STK_MATCH_CACHE_POINT
        OnigStk[k].type = STK_ATOMIC_MATCH_CACHE_POINT
      end
    end
    k
  end

  # STACK_NULL_CHECK: whether the loop `id` is at its start position. It
  # reads the NULL_CHECK_START entry that the top entry's null_check
  # refers to.
  #: (ptr, word, ptr) -> bool
  def zr_onig_null_check(m, id, s)
    k = zr_onig_stk_at(m, OnigStk[OnigMatch[m].stk - OnigStk.size].null_check) + OnigStk.size
    while true
      k = k - OnigStk.size
      if OnigStk[k].type == STK_NULL_CHECK_START && OnigStk[k].a == id
        return Machine.ptr(OnigStk[k].b) == s
      end
    end
    false
  end

  # The MEMST part of STACK_NULL_CHECK_MEMST(_REC). It scans from the
  # START entry `k` up to the top. Returns 1 when every group is empty and
  # did not move, -1 when every group is empty but moved, and 0 when a
  # group captured text.
  #: (ptr, ptr, ptr) -> word
  def zr_onig_null_check_memst_scan(m, k, s)
    isnull = 1
    top = OnigMatch[m].stk
    while k < top
      if OnigStk[k].type == STK_MEM_START
        if OnigStk[k].d == ONIG_INVALID_STACK_INDEX
          return 0
        end
        if zr_onig_bit_status_at(OnigMatch[m].bt_mem_end, OnigStk[k].a)
          endp = Machine.ptr(OnigStk[zr_onig_stk_at(m, OnigStk[k].d)].b)
        else
          endp = Machine.ptr(OnigStk[k].d)
        end
        if Machine.ptr(OnigStk[zr_onig_stk_at(m, OnigStk[k].c)].b) != endp
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
  #: (ptr, word, ptr) -> word
  def zr_onig_null_check_memst(m, id, s)
    k = zr_onig_stk_at(m, OnigStk[OnigMatch[m].stk - OnigStk.size].null_check) + OnigStk.size
    while true
      k = k - OnigStk.size
      if OnigStk[k].type == STK_NULL_CHECK_START && OnigStk[k].a == id
        if Machine.ptr(OnigStk[k].b) != s
          return 0
        end
        return zr_onig_null_check_memst_scan(m, k, s)
      end
    end
    0
  end

  # STACK_NULL_CHECK_MEMST_REC: the same across subexpression calls. It
  # finds the START entry by nesting level.
  #: (ptr, word, ptr) -> word
  def zr_onig_null_check_memst_rec(m, id, s)
    level = 0
    k = zr_onig_stk_at(m, OnigStk[OnigMatch[m].stk - OnigStk.size].null_check) + OnigStk.size
    while true
      k = k - OnigStk.size
      type = OnigStk[k].type
      if type == STK_NULL_CHECK_START
        if OnigStk[k].a == id
          if level == 0
            if Machine.ptr(OnigStk[k].b) != s
              return 0
            end
            return zr_onig_null_check_memst_scan(m, k, s)
          end
          level -= 1
        end
      elsif type == STK_NULL_CHECK_END
        if OnigStk[k].a == id
          level += 1
        end
      end
    end
    0
  end

  # STACK_GET_REPEAT: returns the REPEAT entry of `id` at this call level.
  #: (ptr, word) -> ptr
  def zr_onig_get_repeat(m, id)
    level = 0
    k = OnigMatch[m].stk
    while true
      k = k - OnigStk.size
      type = OnigStk[k].type
      if type == STK_REPEAT
        if level == 0 && OnigStk[k].c == id
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
  #: (ptr) -> ptr
  def zr_onig_stack_return(m)
    level = 0
    k = OnigMatch[m].stk
    while true
      k = k - OnigStk.size
      type = OnigStk[k].type
      if type == STK_CALL_FRAME
        if level == 0
          return Machine.ptr(OnigStk[k].a)
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
  #: (ptr, word) -> ptr
  def zr_onig_get_mem_start(m, mnum)
    level = 0
    k = OnigMatch[m].stk
    base = OnigMatch[m].stk_base
    while k > base
      k = k - OnigStk.size
      type = OnigStk[k].type
      if (type & STK_MASK_MEM_END_OR_MARK) != 0 && OnigStk[k].a == mnum
        level += 1
      elsif type == STK_MEM_START && OnigStk[k].a == mnum
        if level == 0
          break
        end
        level -= 1
      end
    end
    k
  end

  # mem_is_in_memp: whether `mem` is one of the `num` MemNums at memp.
  #: (word, word, ptr) -> bool
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
  #: (ptr) -> word
  def zr_onig_get_memnum(p)
    Machine.u8(Machine.load8(p, 0)) | (Machine.u8(Machine.load8(p, 1)) << 8)
  end

  # backref_match_at_nested_level: matches the text at the pointer in the
  # word `ps` against the capture of one of the groups at memp, made
  # `nest` call levels up. Returns whether it matched. On a match, it
  # moves the pointer in `ps` past the match.
  #: (ptr, word, word, word, ptr, ptr, ptr) -> bool
  def zr_onig_backref_at_nested_level(m, ignore_case, nest, mem_num, memp, ps, send)
    pend = Machine.ptr(0)
    level = 0
    k = OnigMatch[m].stk - OnigStk.size
    base = OnigMatch[m].stk_base
    while k >= base
      type = OnigStk[k].type
      if type == STK_CALL_FRAME
        level -= 1
      elsif type == STK_RETURN
        level += 1
      elsif level == nest
        if type == STK_MEM_START
          if zr_onig_mem_in_memp(OnigStk[k].a, mem_num, memp)
            pstart = Machine.ptr(OnigStk[k].b)
            if pend != 0
              s = Machine.ptr(Machine.load64(ps, 0))
              return false if pend - pstart > send - s
              if ignore_case != 0
                ss = zr_onig_string_cmp_ic(OnigMatch[m].enc, OnigMatch[m].case_fold, pstart, s, Machine.word(pend - pstart), send)
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
          if zr_onig_mem_in_memp(OnigStk[k].a, mem_num, memp)
            pend = Machine.ptr(OnigStk[k].b)
          end
        end
      end
      k = k - OnigStk.size
    end
    false
  end
end
