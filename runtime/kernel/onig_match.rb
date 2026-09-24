# match_at (regexec.c:2311-4234): Onigmo's byte-code interpreter over a
# program the core compiled (runtime/core/regexp/onig/program.rb). The opcode
# families are defs over the OnigMatch state; each answers 0 to go on,
# 1 to fail (backtrack), 2 to finish, or an error code. Derived from
# Onigmo; the license is in runtime/kernel/regexp.rb.
Machine.import "clock_gettime", [I32, Ptr] => I32

# The program header, in runtime/core/regexp/onig/program.rb's field order.
Machine.struct :OnigProg,
  magic: Word, enc_off: Word, options: Word, num_mem: Word, num_repeat: Word,
  num_null_check: Word, num_call: Word, bt_mem_start: Word, bt_mem_end: Word,
  pop_level: Word, code_off: Word, code_len: Word, repeat_off: Word,
  optimize: Word, threshold_len: Word, anchor: Word, sub_anchor: Word,
  anchor_dmin: Word, anchor_dmax: Word, dmin: Word, dmax: Word,
  exact_off: Word, exact_len: Word, map_off: Word, case_fold_flag: Word

# The encoding descriptor of a program (runtime/kernel/onig_enc.rb).
sig [Ptr] => Word
machine def zr_onig_prog_enc(prog)
  Machine.word(prog + OnigProg.enc_off(prog))
end

ONIG_MISMATCH = 0 - 1
ONIGERR_MEMORY = 0 - 5
ONIGERR_UNDEFINED_BYTECODE = 0 - 13
ONIGERR_UNEXPECTED_BYTECODE = 0 - 14
ONIGERR_TIMEOUT = 0 - 23
ONIG_REGION_NOTPOS = 0 - 1
ONIG_INFINITE_DISTANCE = 1 << 62
ONIG_HRTIME_MAX = 1 << 62
ONIG_OPTION_NOTBOL = 1 << 11
ONIG_OPTION_NOTEOL = 1 << 12
ONIG_OPTION_NOTBOS = 1 << 13
ONIG_OPTION_NOTEOS = 1 << 14
ONIG_SIZE_BITSET = 32
ONIG_SIZE_RELADDR = 4
ONIG_SIZE_MEMNUM = 2

OP_FINISH = 0
OP_END = 1
OP_EXACT1 = 2
OP_EXACT2 = 3
OP_EXACT3 = 4
OP_EXACT4 = 5
OP_EXACT5 = 6
OP_EXACTN = 7
OP_EXACTMB2N1 = 8
OP_EXACTMB2N2 = 9
OP_EXACTMB2N3 = 10
OP_EXACTMB2N = 11
OP_EXACTMB3N = 12
OP_EXACTMBN = 13
OP_EXACT1_IC = 14
OP_EXACTN_IC = 15
OP_CCLASS = 16
OP_CCLASS_MB = 17
OP_CCLASS_MIX = 18
OP_CCLASS_NOT = 19
OP_CCLASS_MB_NOT = 20
OP_CCLASS_MIX_NOT = 21
OP_ANYCHAR = 22
OP_ANYCHAR_ML = 23
OP_ANYCHAR_STAR = 24
OP_ANYCHAR_ML_STAR = 25
OP_ANYCHAR_STAR_PEEK_NEXT = 26
OP_ANYCHAR_ML_STAR_PEEK_NEXT = 27
OP_WORD = 28
OP_NOT_WORD = 29
OP_WORD_BOUND = 30
OP_NOT_WORD_BOUND = 31
OP_ASCII_WORD = 34
OP_NOT_ASCII_WORD = 35
OP_ASCII_WORD_BOUND = 36
OP_NOT_ASCII_WORD_BOUND = 37
OP_BEGIN_BUF = 40
OP_END_BUF = 41
OP_BEGIN_LINE = 42
OP_END_LINE = 43
OP_SEMI_END_BUF = 44
OP_BEGIN_POSITION = 45
OP_BACKREF1 = 46
OP_BACKREF2 = 47
OP_BACKREFN = 48
OP_BACKREFN_IC = 49
OP_BACKREF_MULTI = 50
OP_BACKREF_MULTI_IC = 51
OP_BACKREF_WITH_LEVEL = 52
OP_MEMORY_START = 53
OP_MEMORY_START_PUSH = 54
OP_MEMORY_END_PUSH = 55
OP_MEMORY_END_PUSH_REC = 56
OP_MEMORY_END = 57
OP_MEMORY_END_REC = 58
OP_KEEP = 59
OP_FAIL = 60
OP_JUMP = 61
OP_PUSH = 62
OP_POP = 63
OP_PUSH_IF_PEEK_NEXT = 65
OP_REPEAT = 66
OP_REPEAT_NG = 67
OP_REPEAT_INC = 68
OP_REPEAT_INC_NG = 69
OP_REPEAT_INC_SG = 70
OP_REPEAT_INC_NG_SG = 71
OP_NULL_CHECK_START = 72
OP_NULL_CHECK_END = 73
OP_NULL_CHECK_END_MEMST = 74
OP_NULL_CHECK_END_MEMST_PUSH = 75
OP_PUSH_POS = 76
OP_POP_POS = 77
OP_PUSH_POS_NOT = 78
OP_FAIL_POS = 79
OP_PUSH_STOP_BT = 80
OP_POP_STOP_BT = 81
OP_LOOK_BEHIND = 82
OP_PUSH_LOOK_BEHIND_NOT = 83
OP_FAIL_LOOK_BEHIND_NOT = 84
OP_PUSH_ABSENT_POS = 85
OP_ABSENT = 86
OP_ABSENT_END = 87
OP_CALL = 88
OP_RETURN = 89
OP_CONDITION = 90

# The answers of an opcode def.
ONIG_OP_NEXT = 0
ONIG_OP_FAIL = 1
ONIG_OP_FINISH = 2

# A RelAddr, AbsAddr or Length operand: a signed 32-bit little-endian int.
sig [Ptr] => Word
machine def zr_onig_get_i32(p)
  Machine.sword(Machine.load32(p, 0))
end

# BITSET_AT: bit `c` of the 256-bit set at p.
sig [Ptr, Word] => Bool
machine def zr_onig_bitset_at(p, c)
  (Machine.word(Machine.load8(p + (c >> 3), 0)) & (1 << (c & 7))) != 0
end

# The repeat range of repeat `id`: lower, or upper with `which` 1.
sig [Ptr, Word, Word] => Word
machine def zr_onig_repeat_range(m, id, which)
  Machine.load64(OnigMatch.prog(m) + OnigProg.repeat_off(OnigMatch.prog(m)) + (id * 16) + (which * 8), 0)
end

# rb_hrtime_now: monotonic nanoseconds.
sig [] => Word
machine def zr_onig_now
  ts = Machine.slot(16)
  clock_gettime(Machine.i32(CLOCK_MONOTONIC), ts)
  Machine.load64(ts, 0) * 1000000000 + Machine.load64(ts, 8)
end

# CHECK_INTERRUPT_IN_MATCH_AT with rb_reg_timeout_p (re.c): every 128th
# check reads the clock; the first fixes the deadline from the limit,
# the later ones answer whether it passed.
sig [Ptr] => Bool
machine def zr_onig_check_interrupt(m)
  counter = OnigMatch.counter(m) + 1
  if counter < 128
    OnigMatch.set_counter(m, counter)
    return false
  end
  OnigMatch.set_counter(m, 0)
  if OnigMatch.end_time(m) == 0
    limit = OnigMatch.limit(m)
    OnigMatch.set_end_time(m, limit != 0 ? zr_onig_now() + limit : ONIG_HRTIME_MAX)
    return false
  end
  OnigMatch.end_time(m) < zr_onig_now()
end

# OP_END: the match found; the region filled from the memory stacks.
sig [Ptr] => Word
machine def zr_onig_op_end(m)
  s = OnigMatch.s(m)
  str = OnigMatch.str(m)
  n = Machine.word(s - OnigMatch.sstart(m))
  if n > OnigMatch.best_len(m)
    OnigMatch.set_best_len(m, n)
    region = OnigMatch.region(m)
    if region != 0
      pkeep = OnigMatch.pkeep(m)
      Machine.store64(region, 0, Machine.word((pkeep > s ? s : pkeep) - str))
      Machine.store64(region, 8, Machine.word(s - str))
      num_mem = OnigMatch.num_mem(m)
      i = 1
      while i <= num_mem
        if zr_onig_mem_end(m, i) != ONIG_INVALID_STACK_INDEX
          Machine.store64(region + (i * 16), 0, Machine.word(zr_onig_mem_start_ptr(m, i) - str))
          Machine.store64(region + (i * 16), 8, Machine.word(zr_onig_mem_end_ptr(m, i) - str))
        else
          Machine.store64(region + (i * 16), 0, ONIG_REGION_NOTPOS)
          Machine.store64(region + (i * 16), 8, ONIG_REGION_NOTPOS)
        end
        i += 1
      end
    end
  end
  ONIG_OP_FINISH
end

# OP_EXACT1..OP_EXACTN_IC: literal bytes.
sig [Ptr, Word] => Word
machine def zr_onig_op_exact(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  sbegin = s
  if op == OP_EXACT1
    return ONIG_OP_FAIL if s + 1 > e
    return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
    OnigMatch.set_p(m, p + 1)
    OnigMatch.set_s(m, s + 1)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACTN
    tlen = zr_onig_get_i32(p)
    p = p + 4
    return ONIG_OP_FAIL if s + tlen > e
    while tlen > 0
      return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
      p = p + 1
      s = s + 1
      tlen -= 1
    end
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, s - 1)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACT2 || op == OP_EXACT3 || op == OP_EXACT4 || op == OP_EXACT5
    n = op - OP_EXACT1 + 1
    return ONIG_OP_FAIL if s + n > e
    while n > 1
      return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
      p = p + 1
      s = s + 1
      n -= 1
    end
    return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
    OnigMatch.set_sprev(m, s)
    OnigMatch.set_p(m, p + 1)
    OnigMatch.set_s(m, s + 1)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACT1_IC
    return ONIG_OP_FAIL if s + 1 > e
    lowbuf = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
    cell = Machine.slot(8)
    Machine.store64(cell, 0, Machine.word(s))
    len = zr_onig_mbc_case_fold(OnigMatch.enc(m), OnigMatch.case_fold(m), cell, e, lowbuf)
    s = Machine.ptr(Machine.load64(cell, 0))
    return ONIG_OP_FAIL if s > e
    q = lowbuf
    while len > 0
      return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(q, 0)
      p = p + 1
      q = q + 1
      len -= 1
    end
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACTN_IC
    tlen = zr_onig_get_i32(p)
    p = p + 4
    endp = p + tlen
    lowbuf = Machine.slot(ONIG_MBC_CASE_FOLD_MAXLEN)
    cell = Machine.slot(8)
    sprev = OnigMatch.sprev(m)
    while p < endp
      sprev = s
      return ONIG_OP_FAIL if s + 1 > e
      Machine.store64(cell, 0, Machine.word(s))
      len = zr_onig_mbc_case_fold(OnigMatch.enc(m), OnigMatch.case_fold(m), cell, e, lowbuf)
      s = Machine.ptr(Machine.load64(cell, 0))
      return ONIG_OP_FAIL if s > e
      q = lowbuf
      while len > 0
        return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(q, 0)
        p = p + 1
        q = q + 1
        len -= 1
      end
    end
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, sprev)
    return ONIG_OP_NEXT
  end
  zr_onig_op_exact_mb(m, op)
end

# OP_EXACTMB2N1..OP_EXACTMBN: literal multibyte characters.
sig [Ptr, Word] => Word
machine def zr_onig_op_exact_mb(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  sbegin = s
  if op == OP_EXACTMB2N1
    return ONIG_OP_FAIL if s + 2 > e
    return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
    return ONIG_OP_FAIL if Machine.load8(p, 1) != Machine.load8(s, 1)
    OnigMatch.set_p(m, p + 2)
    OnigMatch.set_s(m, s + 2)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACTMB2N2 || op == OP_EXACTMB2N3
    chars = op == OP_EXACTMB2N2 ? 2 : 3
    return ONIG_OP_FAIL if s + (chars * 2) > e
    i = 0
    while i < chars - 1
      return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
      return ONIG_OP_FAIL if Machine.load8(p, 1) != Machine.load8(s, 1)
      p = p + 2
      s = s + 2
      i += 1
    end
    OnigMatch.set_sprev(m, s)
    return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
    return ONIG_OP_FAIL if Machine.load8(p, 1) != Machine.load8(s, 1)
    OnigMatch.set_p(m, p + 2)
    OnigMatch.set_s(m, s + 2)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACTMB2N || op == OP_EXACTMB3N
    width = op == OP_EXACTMB2N ? 2 : 3
    tlen = zr_onig_get_i32(p)
    p = p + 4
    return ONIG_OP_FAIL if s + (tlen * width) > e
    while tlen > 0
      i = 0
      while i < width
        return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
        p = p + 1
        s = s + 1
        i += 1
      end
      tlen -= 1
    end
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, s - width)
    return ONIG_OP_NEXT
  end
  if op == OP_EXACTMBN
    tlen = zr_onig_get_i32(p)
    tlen2 = zr_onig_get_i32(p + 4)
    p = p + 8
    tlen2 = tlen2 * tlen
    return ONIG_OP_FAIL if s + tlen2 > e
    while tlen2 > 0
      return ONIG_OP_FAIL if Machine.load8(p, 0) != Machine.load8(s, 0)
      p = p + 1
      s = s + 1
      tlen2 -= 1
    end
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, s - tlen)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# The cclass_mb tail: a multibyte character against the code ranges
# whose Length operand is at p.
sig [Ptr, Ptr, Ptr, Ptr] => Word
machine def zr_onig_cclass_mb(m, p, s, sbegin)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  tlen = zr_onig_get_i32(p)
  p = p + 4
  return ONIG_OP_FAIL if s + 1 > e
  mb_len = zr_onig_enclen_approx(enc, s, e)
  return ONIG_OP_FAIL if s + mb_len > e
  ss = s
  s = s + mb_len
  code = zr_onig_mbc_to_code(enc, ss, s)
  return ONIG_OP_FAIL if !zr_onig_in_code_range_p(p, code)
  OnigMatch.set_p(m, p + tlen)
  OnigMatch.set_s(m, s)
  OnigMatch.set_sprev(m, sbegin)
  ONIG_OP_NEXT
end

# The cclass_mb_not tail.
sig [Ptr, Ptr, Ptr, Ptr] => Word
machine def zr_onig_cclass_mb_not(m, p, s, sbegin)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  tlen = zr_onig_get_i32(p)
  p = p + 4
  mb_len = zr_onig_enclen(enc, s, e)
  if s + mb_len > e
    return ONIG_OP_FAIL if s + 1 > e
    OnigMatch.set_p(m, p + tlen)
    OnigMatch.set_s(m, e)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  ss = s
  s = s + mb_len
  code = zr_onig_mbc_to_code(enc, ss, s)
  return ONIG_OP_FAIL if zr_onig_in_code_range_p(p, code)
  OnigMatch.set_p(m, p + tlen)
  OnigMatch.set_s(m, s)
  OnigMatch.set_sprev(m, sbegin)
  ONIG_OP_NEXT
end

# OP_CCLASS..OP_CCLASS_MIX_NOT: character classes.
sig [Ptr, Word] => Word
machine def zr_onig_op_cclass(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  sbegin = s
  return ONIG_OP_FAIL if s + 1 > e
  c = Machine.word(Machine.load8(s, 0))
  if op == OP_CCLASS
    return ONIG_OP_FAIL if !zr_onig_bitset_at(p, c)
    OnigMatch.set_p(m, p + ONIG_SIZE_BITSET)
    OnigMatch.set_s(m, s + zr_onig_enclen(enc, s, e))
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_CCLASS_NOT
    return ONIG_OP_FAIL if zr_onig_bitset_at(p, c)
    OnigMatch.set_p(m, p + ONIG_SIZE_BITSET)
    OnigMatch.set_s(m, s + zr_onig_enclen(enc, s, e))
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_CCLASS_MB
    return ONIG_OP_FAIL if !zr_onig_mbc_head_p(enc, s, e)
    return zr_onig_cclass_mb(m, p, s, sbegin)
  end
  if op == OP_CCLASS_MIX
    if zr_onig_mbc_head_p(enc, s, e)
      return zr_onig_cclass_mb(m, p + ONIG_SIZE_BITSET, s, sbegin)
    end
    return ONIG_OP_FAIL if !zr_onig_bitset_at(p, c)
    p = p + ONIG_SIZE_BITSET
    tlen = zr_onig_get_i32(p)
    OnigMatch.set_p(m, p + 4 + tlen)
    OnigMatch.set_s(m, s + 1)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_CCLASS_MB_NOT
    if !zr_onig_mbc_head_p(enc, s, e)
      tlen = zr_onig_get_i32(p)
      OnigMatch.set_p(m, p + 4 + tlen)
      OnigMatch.set_s(m, s + 1)
      OnigMatch.set_sprev(m, sbegin)
      return ONIG_OP_NEXT
    end
    return zr_onig_cclass_mb_not(m, p, s, sbegin)
  end
  if op == OP_CCLASS_MIX_NOT
    if zr_onig_mbc_head_p(enc, s, e)
      return zr_onig_cclass_mb_not(m, p + ONIG_SIZE_BITSET, s, sbegin)
    end
    return ONIG_OP_FAIL if zr_onig_bitset_at(p, c)
    p = p + ONIG_SIZE_BITSET
    tlen = zr_onig_get_i32(p)
    OnigMatch.set_p(m, p + 4 + tlen)
    OnigMatch.set_s(m, s + 1)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_ANYCHAR..OP_ANYCHAR_ML_STAR_PEEK_NEXT: `.` and `.*`.
sig [Ptr, Word] => Word
machine def zr_onig_op_anychar(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  sbegin = s
  if op == OP_ANYCHAR || op == OP_ANYCHAR_ML
    return ONIG_OP_FAIL if s + 1 > e
    n = zr_onig_enclen_approx(enc, s, e)
    return ONIG_OP_FAIL if s + n > e
    if op == OP_ANYCHAR
      return ONIG_OP_FAIL if zr_onig_newline_p(enc, s, e)
    end
    OnigMatch.set_s(m, s + n)
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  sprev = OnigMatch.sprev(m)
  pkeep = OnigMatch.pkeep(m)
  multiline = op == OP_ANYCHAR_ML_STAR || op == OP_ANYCHAR_ML_STAR_PEEK_NEXT
  peek = op == OP_ANYCHAR_STAR_PEEK_NEXT || op == OP_ANYCHAR_ML_STAR_PEEK_NEXT
  pbegin = p - 1
  while s < e
    OnigMatch.set_s(m, s)
    r = zr_onig_check_match_cache(m, pbegin)
    return ONIG_OP_FAIL if r == 1
    if r == 2
      OnigMatch.set_sprev(m, sprev)
      return ONIG_OP_NEXT
    end
    if peek
      if Machine.load8(p, 0) == Machine.load8(s, 0)
        zr_onig_push(m, STK_ALT, p + 1, s, sprev, pkeep)
      else
        OnigMatch.set_num_fails(m, OnigMatch.num_fails(m) + 1)
      end
    else
      zr_onig_push(m, STK_ALT, p, s, sprev, pkeep)
    end
    n = zr_onig_enclen_approx(enc, s, e)
    if multiline
      if n > 1
        return ONIG_OP_FAIL if s + n > e
        sprev = s
        s = s + n
      else
        sprev = s
        s = s + 1
      end
    else
      return ONIG_OP_FAIL if s + n > e
      return ONIG_OP_FAIL if zr_onig_newline_p(enc, s, e)
      sprev = s
      s = s + n
    end
  end
  if peek
    p = p + 1
    sprev = sbegin
  end
  OnigMatch.set_p(m, p)
  OnigMatch.set_s(m, s)
  OnigMatch.set_sprev(m, sprev)
  ONIG_OP_NEXT
end

# OP_WORD..OP_NOT_ASCII_WORD_BOUND: word characters and boundaries.
sig [Ptr, Word] => Word
machine def zr_onig_op_word(m, op)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  str = OnigMatch.str(m)
  sbegin = s
  ascii = op >= OP_ASCII_WORD
  if op == OP_WORD || op == OP_NOT_WORD || op == OP_ASCII_WORD || op == OP_NOT_ASCII_WORD
    return ONIG_OP_FAIL if s + 1 > e
    is = ascii ? zr_onig_mbc_ascii_word_p(enc, s, e) : zr_onig_mbc_word_p(enc, s, e)
    want = op == OP_WORD || op == OP_ASCII_WORD
    return ONIG_OP_FAIL if is != want
    OnigMatch.set_s(m, s + zr_onig_enclen(enc, s, e))
    OnigMatch.set_sprev(m, sbegin)
    return ONIG_OP_NEXT
  end
  if op == OP_WORD_BOUND || op == OP_NOT_WORD_BOUND || op == OP_ASCII_WORD_BOUND || op == OP_NOT_ASCII_WORD_BOUND
    sprev = OnigMatch.sprev(m)
    bound = op == OP_WORD_BOUND || op == OP_ASCII_WORD_BOUND
    if s == str
      if bound
        return ONIG_OP_FAIL if s + 1 > e
        is = ascii ? zr_onig_mbc_ascii_word_p(enc, s, e) : zr_onig_mbc_word_p(enc, s, e)
        return ONIG_OP_FAIL if !is
      else
        if s < e
          is = ascii ? zr_onig_mbc_ascii_word_p(enc, s, e) : zr_onig_mbc_word_p(enc, s, e)
          return ONIG_OP_FAIL if is
        end
      end
    elsif s == e
      was = ascii ? zr_onig_mbc_ascii_word_p(enc, sprev, e) : zr_onig_mbc_word_p(enc, sprev, e)
      return ONIG_OP_FAIL if was != bound
    else
      is = ascii ? zr_onig_mbc_ascii_word_p(enc, s, e) : zr_onig_mbc_word_p(enc, s, e)
      was = ascii ? zr_onig_mbc_ascii_word_p(enc, sprev, e) : zr_onig_mbc_word_p(enc, sprev, e)
      if bound
        return ONIG_OP_FAIL if is == was
      else
        return ONIG_OP_FAIL if is != was
      end
    end
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_BEGIN_BUF..OP_BEGIN_POSITION: anchors.
sig [Ptr, Word] => Word
machine def zr_onig_op_anchor(m, op)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  str = OnigMatch.str(m)
  sprev = OnigMatch.sprev(m)
  mopts = OnigMatch.mopts(m)
  if op == OP_BEGIN_BUF
    return ONIG_OP_FAIL if s != str
    return ONIG_OP_FAIL if (mopts & ONIG_OPTION_NOTBOS) != 0
    return ONIG_OP_NEXT
  end
  if op == OP_END_BUF
    return ONIG_OP_FAIL if s != e
    return ONIG_OP_FAIL if (mopts & ONIG_OPTION_NOTEOS) != 0
    return ONIG_OP_NEXT
  end
  if op == OP_BEGIN_LINE
    if s == str
      return ONIG_OP_FAIL if (mopts & ONIG_OPTION_NOTBOL) != 0
      return ONIG_OP_NEXT
    end
    if zr_onig_newline_p(enc, sprev, e) && s != e
      return ONIG_OP_NEXT
    end
    return ONIG_OP_FAIL
  end
  if op == OP_END_LINE
    if s == e
      return ONIG_OP_FAIL if (mopts & ONIG_OPTION_NOTEOL) != 0
      return ONIG_OP_NEXT
    elsif zr_onig_newline_p(enc, s, e)
      return ONIG_OP_NEXT
    end
    return ONIG_OP_FAIL
  end
  if op == OP_SEMI_END_BUF
    if s == e
      return ONIG_OP_FAIL if (mopts & ONIG_OPTION_NOTEOL) != 0
      return ONIG_OP_NEXT
    elsif zr_onig_newline_p(enc, s, e)
      ss = s + zr_onig_enclen(enc, s, e)
      return ONIG_OP_NEXT if ss == e
    end
    return ONIG_OP_FAIL
  end
  if op == OP_BEGIN_POSITION
    return ONIG_OP_FAIL if s != OnigMatch.gpos(m)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# The capture of group `mem` matched at s, bytewise or folded: the
# position after it, or 0. sprev is left on the last character matched.
sig [Ptr, Word, Word] => Ptr
machine def zr_onig_backref_one(m, mem, ic)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  return Machine.ptr(0) if mem > OnigMatch.num_mem(m)
  return Machine.ptr(0) if zr_onig_mem_end(m, mem) == ONIG_INVALID_STACK_INDEX
  return Machine.ptr(0) if zr_onig_mem_start(m, mem) == ONIG_INVALID_STACK_INDEX
  pstart = zr_onig_mem_start_ptr(m, mem)
  pend = zr_onig_mem_end_ptr(m, mem)
  n = Machine.word(pend - pstart)
  return Machine.ptr(0) if s + n > e
  sprev = s
  if ic != 0
    s = zr_onig_string_cmp_ic(enc, OnigMatch.case_fold(m), pstart, s, n, e)
    return Machine.ptr(0) if s == 0
  else
    q = pstart
    while n > 0
      return Machine.ptr(0) if Machine.load8(q, 0) != Machine.load8(s, 0)
      q = q + 1
      s = s + 1
      n -= 1
    end
  end
  while true
    len = zr_onig_enclen_approx(enc, sprev, e)
    break if sprev + len >= s
    sprev = sprev + len
  end
  OnigMatch.set_sprev(m, sprev)
  s
end

# OP_BACKREF1..OP_BACKREF_WITH_LEVEL: back references.
sig [Ptr, Word] => Word
machine def zr_onig_op_backref(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  if op == OP_BACKREF1 || op == OP_BACKREF2 || op == OP_BACKREFN || op == OP_BACKREFN_IC
    if op == OP_BACKREF1
      mem = 1
    elsif op == OP_BACKREF2
      mem = 2
    else
      mem = zr_onig_get_memnum(p)
      p = p + ONIG_SIZE_MEMNUM
    end
    ns = zr_onig_backref_one(m, mem, op == OP_BACKREFN_IC ? 1 : 0)
    return ONIG_OP_FAIL if ns == 0
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, ns)
    return ONIG_OP_NEXT
  end
  if op == OP_BACKREF_MULTI || op == OP_BACKREF_MULTI_IC
    tlen = zr_onig_get_i32(p)
    p = p + 4
    i = 0
    while i < tlen
      mem = zr_onig_get_memnum(p)
      p = p + ONIG_SIZE_MEMNUM
      if zr_onig_mem_end(m, mem) != ONIG_INVALID_STACK_INDEX && zr_onig_mem_start(m, mem) != ONIG_INVALID_STACK_INDEX
        pstart = zr_onig_mem_start_ptr(m, mem)
        pend = zr_onig_mem_end_ptr(m, mem)
        n = Machine.word(pend - pstart)
        if s + n <= e
          sprev = s
          if op == OP_BACKREF_MULTI_IC
            swork = zr_onig_string_cmp_ic(enc, OnigMatch.case_fold(m), pstart, s, n, e)
          else
            swork = s
            q = pstart
            while n > 0
              if Machine.load8(q, 0) != Machine.load8(swork, 0)
                swork = Machine.ptr(0)
                break
              end
              q = q + 1
              swork = swork + 1
              n -= 1
            end
          end
          if swork != 0
            s = swork
            while true
              len = op == OP_BACKREF_MULTI_IC ? zr_onig_enclen(enc, sprev, e) : zr_onig_enclen_approx(enc, sprev, e)
              break if sprev + len >= s
              sprev = sprev + len
            end
            OnigMatch.set_sprev(m, sprev)
            OnigMatch.set_p(m, p + (ONIG_SIZE_MEMNUM * (tlen - i - 1)))
            OnigMatch.set_s(m, s)
            return ONIG_OP_NEXT
          end
        end
      end
      i += 1
    end
    return ONIG_OP_FAIL
  end
  if op == OP_BACKREF_WITH_LEVEL
    ic = Machine.word(Machine.load32(p, 0))
    level = zr_onig_get_i32(p + 4)
    tlen = zr_onig_get_i32(p + 8)
    p = p + 12
    sprev = s
    cell = Machine.slot(8)
    Machine.store64(cell, 0, Machine.word(s))
    if zr_onig_backref_at_nested_level(m, ic, level, tlen, p, cell, e)
      s = Machine.ptr(Machine.load64(cell, 0))
      while true
        len = zr_onig_enclen(enc, sprev, e)
        break if sprev + len >= s
        sprev = sprev + len
      end
      OnigMatch.set_sprev(m, sprev)
      OnigMatch.set_p(m, p + (ONIG_SIZE_MEMNUM * tlen))
      OnigMatch.set_s(m, s)
      return ONIG_OP_NEXT
    end
    return ONIG_OP_FAIL
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_MEMORY_START..OP_KEEP: capture groups and \K.
sig [Ptr, Word] => Word
machine def zr_onig_op_memory(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  if op == OP_KEEP
    OnigMatch.set_pkeep(m, s)
    return ONIG_OP_NEXT
  end
  mem = zr_onig_get_memnum(p)
  OnigMatch.set_p(m, p + ONIG_SIZE_MEMNUM)
  if op == OP_MEMORY_START_PUSH
    zr_onig_push_mem_start(m, mem, s)
    return ONIG_OP_NEXT
  end
  if op == OP_MEMORY_START
    zr_onig_set_mem_start(m, mem, Machine.word(s))
    zr_onig_set_mem_end(m, mem, ONIG_INVALID_STACK_INDEX)
    return ONIG_OP_NEXT
  end
  if op == OP_MEMORY_END_PUSH
    zr_onig_push_mem_end(m, mem, s)
    return ONIG_OP_NEXT
  end
  if op == OP_MEMORY_END
    zr_onig_set_mem_end(m, mem, Machine.word(s))
    return ONIG_OP_NEXT
  end
  if op == OP_MEMORY_END_PUSH_REC
    stkp = zr_onig_get_mem_start(m, mem)
    zr_onig_set_mem_start(m, mem, zr_onig_stk_index(m, stkp))
    zr_onig_push_mem_end(m, mem, s)
    return ONIG_OP_NEXT
  end
  if op == OP_MEMORY_END_REC
    zr_onig_set_mem_end(m, mem, Machine.word(s))
    stkp = zr_onig_get_mem_start(m, mem)
    if zr_onig_bit_status_at(OnigMatch.bt_mem_start(m), mem)
      zr_onig_set_mem_start(m, mem, zr_onig_stk_index(m, stkp))
    else
      zr_onig_set_mem_start(m, mem, OnigStk.b(stkp))
    end
    zr_onig_push_mem_end_mark(m, mem)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# The repeat_inc tail shared by OP_REPEAT_INC and OP_REPEAT_INC_SG;
# `pbegin` is the opcode's address, 0 for the SG form the cache skips.
sig [Ptr, Word, Word, Ptr, Ptr] => Word
machine def zr_onig_repeat_inc(m, mem, si, p, pbegin)
  stkp = zr_onig_stk_at(m, si)
  count = OnigStk.a(stkp) + 1
  OnigStk.set_a(stkp, count)
  if count >= zr_onig_repeat_range(m, mem, 1)
    # end of repeat. Nothing to do.
  elsif count >= zr_onig_repeat_range(m, mem, 0)
    if pbegin != 0
      r = zr_onig_check_match_cache(m, pbegin)
      if r != 0
        # MATCH_CACHE_HIT: the count this visit added comes off again.
        OnigStk.set_a(stkp, OnigStk.a(stkp) - 1)
        return ONIG_OP_FAIL if r == 1
        return ONIG_OP_NEXT
      end
    end
    zr_onig_push(m, STK_ALT, p, OnigMatch.s(m), OnigMatch.sprev(m), OnigMatch.pkeep(m))
    p = Machine.ptr(OnigStk.b(zr_onig_stk_at(m, si)))
  else
    p = Machine.ptr(OnigStk.b(stkp))
  end
  zr_onig_push_repeat_inc(m, si)
  OnigMatch.set_p(m, p)
  return ONIGERR_TIMEOUT if zr_onig_check_interrupt(m)
  ONIG_OP_NEXT
end

# The repeat_inc_ng tail shared by OP_REPEAT_INC_NG and OP_REPEAT_INC_NG_SG.
sig [Ptr, Word, Word, Ptr, Ptr] => Word
machine def zr_onig_repeat_inc_ng(m, mem, si, p, pbegin)
  stkp = zr_onig_stk_at(m, si)
  count = OnigStk.a(stkp) + 1
  OnigStk.set_a(stkp, count)
  upper = zr_onig_repeat_range(m, mem, 1)
  if count < upper
    if count >= zr_onig_repeat_range(m, mem, 0)
      pcode = Machine.ptr(OnigStk.b(stkp))
      zr_onig_push_repeat_inc(m, si)
      if pbegin != 0
        r = zr_onig_check_match_cache(m, pbegin)
        return ONIG_OP_FAIL if r == 1
        return ONIG_OP_NEXT if r == 2
      end
      zr_onig_push(m, STK_ALT, pcode, OnigMatch.s(m), OnigMatch.sprev(m), OnigMatch.pkeep(m))
    else
      p = Machine.ptr(OnigStk.b(stkp))
      zr_onig_push_repeat_inc(m, si)
    end
  elsif count == upper
    zr_onig_push_repeat_inc(m, si)
  end
  OnigMatch.set_p(m, p)
  return ONIGERR_TIMEOUT if zr_onig_check_interrupt(m)
  ONIG_OP_NEXT
end

# OP_FAIL..OP_REPEAT_INC_NG_SG: control flow and repeats.
sig [Ptr, Word] => Word
machine def zr_onig_op_control(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  if op == OP_FAIL
    return ONIG_OP_FAIL
  end
  if op == OP_JUMP
    addr = zr_onig_get_i32(p)
    OnigMatch.set_p(m, p + 4 + addr)
    return ONIGERR_TIMEOUT if zr_onig_check_interrupt(m)
    return ONIG_OP_NEXT
  end
  if op == OP_PUSH
    addr = zr_onig_get_i32(p)
    p = p + 4
    r = zr_onig_check_match_cache(m, p - 5)
    return ONIG_OP_FAIL if r == 1
    return ONIG_OP_NEXT if r == 2
    zr_onig_push(m, STK_ALT, p + addr, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
    OnigMatch.set_p(m, p)
    return ONIG_OP_NEXT
  end
  if op == OP_POP
    OnigMatch.set_stk(m, OnigMatch.stk(m) - OnigStk.size)
    OnigMatch.set_num_fails(m, OnigMatch.num_fails(m) + 1)
    return ONIG_OP_NEXT
  end
  if op == OP_PUSH_IF_PEEK_NEXT
    addr = zr_onig_get_i32(p)
    p = p + 4
    r = zr_onig_check_match_cache(m, p - 5)
    return ONIG_OP_FAIL if r == 1
    return ONIG_OP_NEXT if r == 2
    if Machine.load8(p, 0) == Machine.load8(s, 0)
      p = p + 1
      zr_onig_push(m, STK_ALT, p + addr, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
      OnigMatch.set_p(m, p)
      return ONIG_OP_NEXT
    end
    OnigMatch.set_num_fails(m, OnigMatch.num_fails(m) + 1)
    OnigMatch.set_p(m, p + 1)
    return ONIG_OP_NEXT
  end
  if op == OP_REPEAT || op == OP_REPEAT_NG
    mem = zr_onig_get_memnum(p)
    addr = zr_onig_get_i32(p + ONIG_SIZE_MEMNUM)
    p = p + ONIG_SIZE_MEMNUM + 4
    zr_onig_stack_ensure(m)
    Machine.store64(OnigMatch.repeat_stk(m) + (mem * 8), 0, zr_onig_stk_index(m, OnigMatch.stk(m)))
    zr_onig_push_repeat(m, mem, p)
    if zr_onig_repeat_range(m, mem, 0) == 0
      r = zr_onig_check_match_cache(m, p - ONIG_SIZE_MEMNUM - 5)
      return ONIG_OP_FAIL if r == 1
      return ONIG_OP_NEXT if r == 2
      if op == OP_REPEAT
        zr_onig_push(m, STK_ALT, p + addr, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
      else
        zr_onig_push(m, STK_ALT, p, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
        p = p + addr
      end
    end
    OnigMatch.set_p(m, p)
    return ONIG_OP_NEXT
  end
  if op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG
    mem = zr_onig_get_memnum(p)
    p = p + ONIG_SIZE_MEMNUM
    si = Machine.load64(OnigMatch.repeat_stk(m) + (mem * 8), 0)
    if op == OP_REPEAT_INC
      return zr_onig_repeat_inc(m, mem, si, p, p - ONIG_SIZE_MEMNUM - 1)
    end
    return zr_onig_repeat_inc_ng(m, mem, si, p, p - ONIG_SIZE_MEMNUM - 1)
  end
  if op == OP_REPEAT_INC_SG || op == OP_REPEAT_INC_NG_SG
    mem = zr_onig_get_memnum(p)
    p = p + ONIG_SIZE_MEMNUM
    si = zr_onig_stk_index(m, zr_onig_get_repeat(m, mem))
    if op == OP_REPEAT_INC_SG
      return zr_onig_repeat_inc(m, mem, si, p, Machine.ptr(0))
    end
    return zr_onig_repeat_inc_ng(m, mem, si, p, Machine.ptr(0))
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# null_check_found: the empty loop found, skip the instruction after.
sig [Ptr, Ptr] => Word
machine def zr_onig_null_check_found(m, p)
  op = Machine.word(Machine.load8(p, 0))
  p = p + 1
  if op == OP_JUMP || op == OP_PUSH
    OnigMatch.set_p(m, p + ONIG_SIZE_RELADDR)
    return ONIG_OP_NEXT
  end
  if op == OP_REPEAT_INC || op == OP_REPEAT_INC_NG || op == OP_REPEAT_INC_SG || op == OP_REPEAT_INC_NG_SG
    OnigMatch.set_p(m, p + ONIG_SIZE_MEMNUM)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNEXPECTED_BYTECODE
end

# OP_NULL_CHECK_START..OP_NULL_CHECK_END_MEMST_PUSH: empty-loop checks.
sig [Ptr, Word] => Word
machine def zr_onig_op_null_check(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  mem = zr_onig_get_memnum(p)
  p = p + ONIG_SIZE_MEMNUM
  OnigMatch.set_p(m, p)
  if op == OP_NULL_CHECK_START
    zr_onig_push_null_check_start(m, mem, s)
    return ONIG_OP_NEXT
  end
  if op == OP_NULL_CHECK_END
    if zr_onig_null_check(m, mem, s)
      return zr_onig_null_check_found(m, p)
    end
    return ONIG_OP_NEXT
  end
  if op == OP_NULL_CHECK_END_MEMST
    isnull = zr_onig_null_check_memst(m, mem, s)
    if isnull != 0
      return ONIG_OP_FAIL if isnull == 0 - 1
      return zr_onig_null_check_found(m, p)
    end
    return ONIG_OP_NEXT
  end
  if op == OP_NULL_CHECK_END_MEMST_PUSH
    isnull = zr_onig_null_check_memst_rec(m, mem, s)
    if isnull != 0
      return ONIG_OP_FAIL if isnull == 0 - 1
      return zr_onig_null_check_found(m, p)
    end
    zr_onig_push_null_check_end(m, mem)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_PUSH_POS..OP_FAIL_LOOK_BEHIND_NOT: look-around and atomic groups.
sig [Ptr, Word] => Word
machine def zr_onig_op_pos(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  str = OnigMatch.str(m)
  if op == OP_PUSH_POS
    zr_onig_push(m, STK_POS, Machine.ptr(0), s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
    return ONIG_OP_NEXT
  end
  if op == OP_POP_POS
    stkp = zr_onig_stack_void_til(m, STK_POS)
    OnigMatch.set_s(m, Machine.ptr(OnigStk.b(stkp)))
    OnigMatch.set_sprev(m, Machine.ptr(OnigStk.c(stkp)))
    return ONIG_OP_NEXT
  end
  if op == OP_PUSH_POS_NOT
    addr = zr_onig_get_i32(p)
    p = p + 4
    zr_onig_push(m, STK_POS_NOT, p + addr, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
    OnigMatch.set_p(m, p)
    return ONIG_OP_NEXT
  end
  if op == OP_FAIL_POS
    zr_onig_stack_pop_til(m, STK_POS_NOT)
    return ONIG_OP_FAIL
  end
  if op == OP_PUSH_STOP_BT
    zr_onig_push_type(m, STK_STOP_BT)
    return ONIG_OP_NEXT
  end
  if op == OP_POP_STOP_BT
    zr_onig_stack_void_til(m, STK_STOP_BT)
    return ONIG_OP_NEXT
  end
  if op == OP_LOOK_BEHIND
    tlen = zr_onig_get_i32(p)
    p = p + 4
    s = zr_onig_step_back(enc, str, s, e, tlen)
    return ONIG_OP_FAIL if s == 0
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, s)
    OnigMatch.set_sprev(m, zr_onig_prev_char_head(enc, str, s, e))
    return ONIG_OP_NEXT
  end
  if op == OP_PUSH_LOOK_BEHIND_NOT
    addr = zr_onig_get_i32(p)
    tlen = zr_onig_get_i32(p + 4)
    p = p + 8
    q = zr_onig_step_back(enc, str, s, e, tlen)
    if q == 0
      # too short case -> success. ex. /(?<!XXX)a/.match("a")
      OnigMatch.set_p(m, p + addr)
      return ONIG_OP_NEXT
    end
    zr_onig_push(m, STK_LOOK_BEHIND_NOT, p + addr, s, OnigMatch.sprev(m), OnigMatch.pkeep(m))
    OnigMatch.set_p(m, p)
    OnigMatch.set_s(m, q)
    OnigMatch.set_sprev(m, zr_onig_prev_char_head(enc, str, q, e))
    return ONIG_OP_NEXT
  end
  if op == OP_FAIL_LOOK_BEHIND_NOT
    zr_onig_stack_pop_til(m, STK_LOOK_BEHIND_NOT)
    return ONIG_OP_FAIL
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_PUSH_ABSENT_POS..OP_ABSENT_END: absent operator (?~...).
sig [Ptr, Word] => Word
machine def zr_onig_op_absent(m, op)
  p = OnigMatch.p(m)
  s = OnigMatch.s(m)
  e = OnigMatch.aend(m)
  enc = OnigMatch.enc(m)
  sprev = OnigMatch.sprev(m)
  pkeep = OnigMatch.pkeep(m)
  if op == OP_PUSH_ABSENT_POS
    # Save the absent-start-pos and the original end-pos.
    zr_onig_push_absent_pos(m, s, e)
    return ONIG_OP_NEXT
  end
  if op == OP_ABSENT
    aend = e
    selfp = p - 1
    # STACK_POP_ABSENT_POS: restore end-pos.
    stk = OnigMatch.stk(m) - OnigStk.size
    OnigMatch.set_stk(m, stk)
    absent = Machine.ptr(OnigStk.a(stk))
    e = Machine.ptr(OnigStk.b(stk))
    OnigMatch.set_aend(m, e)
    addr = zr_onig_get_i32(p)
    p = p + 4
    if absent > aend && s > absent
      # An empty match occurred in (?~...) at the start point. Never match.
      zr_onig_stack_pop(m)
      return ONIG_OP_FAIL
    elsif s >= aend && s > absent
      # Only one (or less) character matched in the last iteration: not a possible point.
      return ONIG_OP_FAIL if s > aend
      # All possible points were found. Try matching after (?~...).
      return ONIG_OP_FAIL if s > e
      OnigMatch.set_p(m, p + addr)
    elsif s == e
      # At the end of the string, just match with it.
      return ONIG_OP_FAIL if s > e
      OnigMatch.set_p(m, p + addr)
    else
      zr_onig_push(m, STK_ALT, p + addr, s, sprev, pkeep)
      n = zr_onig_enclen(enc, s, e)
      zr_onig_push_absent_pos(m, absent, e)
      zr_onig_push(m, STK_ALT, selfp, s + n, s, pkeep)
      zr_onig_push_type(m, STK_ABSENT)
      OnigMatch.set_aend(m, aend)
      OnigMatch.set_p(m, p)
    end
    return ONIG_OP_NEXT
  end
  if op == OP_ABSENT_END
    # The pattern inside (?~...) was matched: set the end-pos temporarily
    # and go to the next iteration.
    if sprev < e
      OnigMatch.set_aend(m, sprev)
    end
    zr_onig_stack_pop_til(m, STK_ABSENT)
    return ONIG_OP_FAIL
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# OP_CALL, OP_RETURN, OP_CONDITION.
sig [Ptr, Word] => Word
machine def zr_onig_op_call(m, op)
  p = OnigMatch.p(m)
  if op == OP_CALL
    addr = zr_onig_get_i32(p)
    p = p + 4
    zr_onig_push_call_frame(m, p)
    OnigMatch.set_p(m, OnigMatch.code(m) + addr)
    return ONIG_OP_NEXT
  end
  if op == OP_RETURN
    OnigMatch.set_p(m, zr_onig_stack_return(m))
    zr_onig_push_type(m, STK_RETURN)
    return ONIG_OP_NEXT
  end
  if op == OP_CONDITION
    mem = zr_onig_get_memnum(p)
    addr = zr_onig_get_i32(p + ONIG_SIZE_MEMNUM)
    p = p + ONIG_SIZE_MEMNUM + 4
    if mem > OnigMatch.num_mem(m) || zr_onig_mem_end(m, mem) == ONIG_INVALID_STACK_INDEX || zr_onig_mem_start(m, mem) == ONIG_INVALID_STACK_INDEX
      p = p + addr
    end
    OnigMatch.set_p(m, p)
    return ONIG_OP_NEXT
  end
  ONIGERR_UNDEFINED_BYTECODE
end

# One opcode: dispatched by family.
sig [Ptr, Word] => Word
machine def zr_onig_step(m, op)
  if op < OP_CCLASS
    return zr_onig_op_end(m) if op == OP_END
    return ONIG_OP_FINISH if op == OP_FINISH
    return zr_onig_op_exact(m, op)
  end
  if op < OP_BEGIN_BUF
    return zr_onig_op_cclass(m, op) if op < OP_ANYCHAR
    return zr_onig_op_anychar(m, op) if op < OP_WORD
    return zr_onig_op_word(m, op)
  end
  if op < OP_FAIL
    return zr_onig_op_anchor(m, op) if op < OP_BACKREF1
    return zr_onig_op_backref(m, op) if op < OP_MEMORY_START
    return zr_onig_op_memory(m, op)
  end
  return zr_onig_op_control(m, op) if op < OP_NULL_CHECK_START
  return zr_onig_op_null_check(m, op) if op < OP_PUSH_POS
  return zr_onig_op_pos(m, op) if op < OP_PUSH_ABSENT_POS
  return zr_onig_op_absent(m, op) if op < OP_CALL
  zr_onig_op_call(m, op)
end

# match_at: the match of the program at sstart, sprev the character
# before it (0 at the start); the length matched, ONIG_MISMATCH, or an
# error (ONIGERR_TIMEOUT among them). The region and the stacks are the
# search's.
sig [Ptr, Ptr, Ptr] => Word
machine def zr_onig_match_at(m, sstart, sprev)
  # STACK_INIT: the stack a former match_at grew stays; else the arena's.
  if OnigMatch.stack_p(m) != 0
    base = OnigMatch.stack_p(m)
    OnigMatch.set_stk_base(m, base)
    OnigMatch.set_stk_end(m, base + (OnigMatch.stack_n(m) * OnigStk.size))
  else
    base = OnigMatch.stk_alloc(m)
    OnigMatch.set_stk_base(m, base)
    OnigMatch.set_stk_end(m, base + (ONIG_INIT_MATCH_STACK_SIZE * OnigStk.size))
  end
  OnigMatch.set_stk(m, base)
  # STACK_PUSH_ENSURED(STK_ALT, FinishCode): the bottom entry, whose code
  # is the program's closing OP_FINISH.
  code = OnigMatch.code(m)
  finish = code + OnigProg.code_len(OnigMatch.prog(m)) - 1
  zr_onig_push(m, STK_ALT, finish, sstart, sprev, sstart)
  num_mem = OnigMatch.num_mem(m)
  i = 0
  while i <= num_mem
    zr_onig_set_mem_start(m, i, ONIG_INVALID_STACK_INDEX)
    zr_onig_set_mem_end(m, i, ONIG_INVALID_STACK_INDEX)
    i += 1
  end
  OnigMatch.set_best_len(m, ONIG_MISMATCH)
  OnigMatch.set_sstart(m, sstart)
  OnigMatch.set_s(m, sstart)
  OnigMatch.set_pkeep(m, sstart)
  OnigMatch.set_sprev(m, sprev)
  OnigMatch.set_p(m, OnigMatch.code(m))
  OnigMatch.set_aend(m, OnigMatch.text_end(m))
  result = ONIG_MISMATCH
  while true
    p = OnigMatch.p(m)
    op = Machine.word(Machine.load8(p, 0))
    OnigMatch.set_p(m, p + 1)
    r = zr_onig_step(m, op)
    if r == ONIG_OP_FAIL
      zr_onig_stack_pop(m)
      stk = OnigMatch.stk(m)
      OnigMatch.set_p(m, Machine.ptr(OnigStk.a(stk)))
      OnigMatch.set_s(m, Machine.ptr(OnigStk.b(stk)))
      OnigMatch.set_sprev(m, Machine.ptr(OnigStk.c(stk)))
      OnigMatch.set_pkeep(m, Machine.ptr(OnigStk.d(stk)))
      r = zr_onig_fail_match_cache(m)
      if r < 0
        result = r
        break
      end
      if zr_onig_check_interrupt(m)
        result = ONIGERR_TIMEOUT
        break
      end
    elsif r == ONIG_OP_FINISH
      result = OnigMatch.best_len(m)
      break
    elsif r != ONIG_OP_NEXT
      result = r
      break
    end
  end
  zr_onig_stack_save(m)
  result
end
