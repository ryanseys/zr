# The gate word in its register: `Machine.gates` reads it with no load,
# `Machine.gates_set` writes it for every function at once, with the
# static it also lives in, and `Machine.gates_enter` loads it from the
# static where foreign code enters, as C enters `main` here. What the
# program must see: a write of its own in the same function, a write a
# call makes, and the static holding the same word. Every line is a
# tally ruby can check by hand.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

sig [Word] => Void
machine def put_word(n)
  buf = Machine.slot(24)
  at = 23
  Machine.store8(buf + at, 0, Machine.i8(10))
  if n == 0
    at = at - 1
    Machine.store8(buf + at, 0, Machine.i8(48))
  end
  while n > 0
    at = at - 1
    Machine.store8(buf + at, 0, Machine.i8(48 + (n % 10)))
    n = n / 10
  end
  write(1, buf + at, 24 - at)
end

# A loop keeps this def a call, so its write happens behind one.
sig [Word] => Void
machine def set_gates(v)
  k = 0
  while k < 1
    Machine.gates_set(v)
    k = k + 1
  end
end

# Reads at every turn, with a call on two of them: over eight turns the
# sum is 0 + 0 + (0 + 10) + (10 + 100) + 4 * (100 + 100) = 920.
sig [Word] => Word
machine def tally(n)
  sum = 0
  i = 0
  while i < n
    sum = sum + Machine.gates
    set_gates(10) if i == 2
    set_gates(100) if i == 3
    sum = sum + Machine.gates
    i = i + 1
  end
  sum
end

# A write of the function's own is what every later read gets, and so
# is a call's: 1 + 2 + 2 + 3 = 8, and the static holds the 3 as well,
# so 11.
sig [] => Word
machine def own_write
  Machine.gates_set(1)
  sum = Machine.gates
  Machine.gates_set(2)
  sum = sum + Machine.gates + Machine.gates
  set_gates(3)
  sum = sum + Machine.gates
  sum + Machine.load64(Machine.static(:gates, 8), 0)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  Machine.gates_enter
  put_word(tally(8))
  put_word(own_write())
  exit(0)
  0
end
