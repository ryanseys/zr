# A chained poly `+` whose later operand allocates.
#
# `a + b + c` on operands of unknown type computes `(a + b) + c`. The inner
# result is a fresh string that no variable holds, and `c` is evaluated after
# it. An allocation there can start a GC, and the inner result must survive
# it, so the outer `+` reads the right text.

def build_name(prefix, mid, i)
  prefix + mid + i.to_s
end

# an Integer call site widens the parameters to "any type", so the `+`
# dispatches at run time
def widen_them
  build_name(1, 2, 0)
end

s = ""
i = 0
while i < 2000
  s = build_name("blk.", "attn_k.head_", i)
  i += 1
end
p s
p s.length

# the same shape with the allocating operand in the middle
def middle(a, b)
  a + b.to_s + "!"
end

def widen_middle
  middle(1, 2)
end

p middle("n=", 41)

# a longer chain: every intermediate has to survive the next operand
def four(a, b, c, d)
  a + b + c + d
end

def widen_four
  four(1, 2, 3, 4)
end

p four("a", "b", 3.to_s, "d")
