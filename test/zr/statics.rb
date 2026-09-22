# The kernel's guard words as values: `IR::Statics` reads `gates` once
# at entry and again after each call, and a loop of reads between calls
# reads none. What the program must still see: a store of its own in
# the same function, a store a call makes, and a store behind a pointer
# to the word that a call handed out. A static that is not promoted --
# the task slot, whose poll word the timer thread writes -- is read
# afresh every time. Every line is a tally ruby can check by hand.
Machine.import "write", [I32, Ptr, Word] => Word
Machine.import "exit", [I32] => Void

sig [] => Ptr
machine def gates
  Machine.static(:gates, 8)
end

# task: 0 the task pointer, 8 the poll word
sig [] => Ptr
machine def task
  Machine.static(:current_task, 16)
end

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

# A loop keeps this def a call, so its store is behind one.
sig [Word] => Void
machine def set_gates(v)
  k = 0
  while k < 1
    Machine.store64(gates(), 0, v)
    k = k + 1
  end
end

# The word's address, from a call: a store through it is a store the
# reader cannot tell from any other, and the call it came from is what
# makes the reader reload.
sig [] => Ptr
machine def gates_from_afar
  k = 0
  p = gates()
  while k < 1
    p = gates()
    k = k + 1
  end
  p
end

# Reads at every turn, with a call on two of them: over eight turns the
# sum is 0 + 0 + (0 + 10) + (10 + 100) + 4 * (100 + 100) = 920.
sig [Word] => Word
machine def tally(n)
  sum = 0
  i = 0
  while i < n
    sum = sum + Machine.load64(gates(), 0)
    set_gates(10) if i == 2
    set_gates(100) if i == 3
    sum = sum + Machine.load64(gates(), 0)
    i = i + 1
  end
  sum
end

# A store of the function's own is the value every later read gets,
# until a call; and a call that hands the address out, then a store
# through it: 1 + 2 + 2 + 3 + 4 = 12 -- the read after the call sees 3
# written through the pointer, only because the call made it reload.
sig [] => Word
machine def own_store
  g = gates()
  Machine.store64(g, 0, 1)
  sum = Machine.load64(g, 0)
  Machine.store64(g, 0, 2)
  sum = sum + Machine.load64(g, 0) + Machine.load64(g, 0)
  p = gates_from_afar()
  Machine.store64(p, 0, 3)
  sum = sum + Machine.load64(g, 0)
  set_gates(4)
  sum + Machine.load64(g, 0)
end

# Neither word of the task slot is promoted: a store to the poll word
# between two reads of it shows in the second.
sig [] => Word
machine def poll
  t = task()
  Machine.store64(t, 0, 5)
  Machine.store64(t, 8, 1)
  a = Machine.load64(t, 0) + Machine.load64(t, 8)
  Machine.store64(t, 8, 2)
  a + Machine.load64(t, 0) + Machine.load64(t, 8)
end

sig [I32, Ptr] => I32
machine def main(argc, argv)
  put_word(tally(8))
  put_word(own_store())
  put_word(poll())
  exit(0)
  0
end
