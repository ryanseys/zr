# Short circuit, negation, unless and constants: `&&` and `||` lower the
# right side only when the left decides nothing, which the tally of
# `probe` calls proves; every fact is one bit of the exit status.
module Zr::Kern
  Libc.import :exit, [I32] => Void

  ONE = 1
  MASK = ONE << 4 | 3
  NEG = -5
  LIMIT = (MASK + ONE) * 2

  # calls: 0 the tally of probe calls
  #: () -> ptr
  def calls
    Machine.static(:calls, 8)
  end

  #: (bool) -> bool
  def probe(answer)
    c = calls()
    Machine.store64(c, 0, Machine.load64(c, 0) + 1)
    answer
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    code = 0
    code = code | 1 if MASK != 19
    code = code | 2 unless LIMIT == 40
    code = code | 4 if NEG + 5 != 0
    code = code | 8 unless -NEG == 5
    # false && probe: probe is not called
    if false && probe(true)
      code = code | 16
    end
    code = code | 32 if Machine.load64(calls(), 0) != 0
    # true || probe: probe is not called
    unless true || probe(false)
      code = code | 64
    end
    code = code | 128 if Machine.load64(calls(), 0) != 0
    # both sides run when the left decides nothing
    ok = probe(true) && probe(true)
    code = code | 256 unless ok
    code = code | 512 if Machine.load64(calls(), 0) != 2
    ok = probe(false) || probe(false)
    code = code | 1024 if ok
    code = code | 2048 if Machine.load64(calls(), 0) != 4
    # `!` on a Bool and on a Word, and `&&` as a Word condition
    code = code | 4096 if !true
    code = code | 8192 unless !0
    n = 7
    code = code | 16384 unless n && n - 7 == 0
    code = code | 32768 if !n
    # unless as a value
    m = unless n > 5 then 1 else 2 end
    code = code | 65536 if m != 2
    # a loop whose test is a conjunction asks the right side each turn,
    # and not on the turn the left side ends
    i = 0
    while i < 3 && probe(true)
      i += 1
    end
    code = code | 131072 if i != 3 || Machine.load64(calls(), 0) != 7
    # three tests in one, the last decided by the middle one
    code = code | 262144 if i == 0 || (i == 3 && probe(false)) || i != 3
    code = code | 524288 if Machine.load64(calls(), 0) != 8
    # The status holds eight bits: the facts past them fold onto the low ones.
    Libc.exit(Machine.i32((code & 255) | (code >> 8)))
    0
  end
end
