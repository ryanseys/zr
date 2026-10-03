# Guard clauses in small defs: a `return` ahead of the body is the
# shape most one-line kernel defs open with, and a call to such a def
# lowers its body in place, the return a jump to the end of it. Each
# def below answers one letter, and the letters must spell the line.
module Zr::Kern
  Libc.import :write, [I32, Ptr, Word] => Word
  Libc.import :exit, [I32] => Void

  # The letters, as bytes. Every answer of the defs below is one, so
  # the arguments a body is meant to answer for sit above them all.
  A = 97
  B = 98
  C = 99
  D = 100
  E = 101
  F = 102
  LINE = 10

  # `a` for zero, else `b`.
  #: (word) -> word
  def zero_or_not(n)
    return A if n == 0

    B
  end

  # A guard that answers, and a body that computes: the letter after n.
  #: (word) -> word
  def clamp(n)
    return C if n > 200
    return D if n < 0

    n + 1
  end

  # Both arms return; nothing falls through.
  #: (bool) -> word
  def either(flag)
    if flag
      return E
    else
      return F
    end
  end

  # A guard in a def that answers nothing: the write is skipped.
  #: (word, ptr) -> void
  def put_unless_zero(n, buf)
    return if n == 0

    Machine.store8(buf, 0, Machine.i8(n))
    Libc.write(1, buf, 1)
  end

  # A guarded def called from a guarded def: the exits nest.
  #: (word) -> word
  def twice_guarded(n)
    return zero_or_not(n) if n < 2

    clamp(n)
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    buf = Machine.slot(8)
    put_unless_zero(zero_or_not(0), buf)     # a
    put_unless_zero(zero_or_not(5), buf)     # b
    put_unless_zero(clamp(500), buf)         # c
    put_unless_zero(clamp(-1), buf)          # d
    put_unless_zero(either(true), buf)       # e
    put_unless_zero(either(false), buf)      # f
    put_unless_zero(0, buf)                  # nothing
    put_unless_zero(clamp(102), buf)         # g
    put_unless_zero(twice_guarded(0), buf)   # a
    put_unless_zero(twice_guarded(103), buf) # h
    # A guarded answer as an operand, and in a condition.
    put_unless_zero(clamp(103) + 1, buf) if zero_or_not(1) == 98 # i
    Machine.store8(buf, 0, Machine.i8(LINE))
    Libc.write(1, buf, 1)
    Libc.exit(0)
    0
  end
end
