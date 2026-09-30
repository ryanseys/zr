# `Integer#[N]` (bit-extraction) where the receiver is an ivar that
# held a String and then an Integer. `int[i]` gives the bit at `i`,
# so a `pc[8] == tmp[8] ? a : b` style page-bit check works.

class T_poly_int_bit_index_Holder
  # Mixed-type ivar writes: first a String, then an Integer.
  def initialize
    @x = "init"
    @x = 0b10110100  # 180 — actual value at test time
  end

  attr_reader :x

  # Same-page check pattern: extract bit 8 from each Integer.
  def same_page?(a, b)
    a[8] == b[8]
  end
end

h = T_poly_int_bit_index_Holder.new
v = h.x  # `v` is the Integer 180 here

# Static index, dynamic value.
puts v[0]    # 0
puts v[1]    # 0
puts v[2]    # 1
puts v[3]    # 0
puts v[4]    # 1
puts v[5]    # 1
puts v[6]    # 0
puts v[7]    # 1

# Dynamic index.
i = 0
while i < 4
  puts v[i]
  i += 1
end

# Page-bit check: `0x100 | x` flips bit 8 on/off so the comparison
# differs depending on input.
puts h.same_page?(h.x, h.x | 0x100)   # false (bit 8 differs)
puts h.same_page?(h.x, h.x | 0x10)    # true (bit 8 same — both 0)
