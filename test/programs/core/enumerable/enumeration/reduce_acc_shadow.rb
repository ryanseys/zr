# Array#reduce: the accumulator block param's type must come from the
# seed (init_val), not from the element type. The type of acc inside
# the block follows the seed in both directions -- a String seed over
# an Integer outer local, and an Integer seed over a String outer local.

def f
  total = [1, 2, 3].reduce("") { |acc, x| acc + x.to_s }
  puts total   # 123
end
f

# Outer same-named local of a different type must not leak into the block.
def g
  acc = 99
  out = [10, 20, 30].reduce("=") { |acc, x| acc + x.to_s }
  puts out   # =102030
  puts acc   # 99
end
g

# Reverse direction: int seed must shadow an outer string acc without
# the outer binding leaking into the block's `acc + x`, which is
# Integer addition, not String concatenation.
def h
  acc = "outer"
  sum = [1, 2, 3, 4, 5].reduce(0) { |acc, x| acc + x }
  puts sum   # 15
  puts acc   # outer
end
h
