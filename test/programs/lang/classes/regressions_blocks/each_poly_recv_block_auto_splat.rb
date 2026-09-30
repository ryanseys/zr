# `arr.each {|a, b| ... }` over an Array of Arrays auto-splats each
# element across the block params, matching CRuby's
# `arr.each {|*args| a, b, *_ = args }` shape. So `b` gets the second
# element. The inner Arrays hold only Integers (as `[i, fixed]` in
# optcarrot's `setup_lut`) or mixed classes.

class T_each_poly_recv_block_auto_splat_C
  def initialize
    @h = {}
  end

  def push_int(bank, pair)
    # `pair` holds only Integers.
    (@h[bank] ||= []) << pair
  end

  def push_poly(bank, pair)
    # `pair` holds mixed classes.
    (@h[bank] ||= []) << pair
  end

  def each_pair(bank)
    arr = @h[bank]
    sum = 0
    arr.each {|a, b| sum += a.to_i + b.to_i }
    sum
  end
end

c = T_each_poly_recv_block_auto_splat_C.new
c.push_int(0, [10, 20])
c.push_int(0, [3,  4])
puts c.each_pair(0)         # 10 + 20 + 3 + 4 = 37

d = T_each_poly_recv_block_auto_splat_C.new
d.push_poly(1, [100, "x"])  # b is a string, in a mixed Array
d.push_poly(1, [5,   "y"])
puts d.each_pair(1)         # 100 + 0 + 5 + 0 = 105 (string `to_i` of "x" / "y" = 0)
