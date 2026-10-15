# Array#sum adds Integers and Rationals exactly, a Float start too, which
# joins the exact sum at the end, as Ruby 4.1's rb_ary_sum does. The first
# Float turns to the compensated walk; anything else adds with +.
big = -(2**62 + 7)
cases = [[[263, big], 0.0], [[263, big], 0], [[263.0, big], 0], [[263, big, 0.5], 0.0], [[263, big, 1r], 0.0], [[263, 2**70], 0.5],
         [[], 0.0], [[1r, 2], 0.0], [[0.1, 0.2, 0.3], 0], [[0.1, 0.2, 0.3], 0.0], [[1, 2], 1r], [[1, 0.5], 1r], [[1, "a"], 0] , [["a", "b"], ""],
         [[1, Float::NAN], 0.0], [[Float::INFINITY, -Float::INFINITY], 0], [[1, 2, 3], Complex(1, 1)], [[0.1, Complex(1, 2)], 0.0], [[1, Complex(0, 1), 0.5], 0.0]]
cases.each do |items, init|
  p [items, init, items.sum(init)]
rescue => e
  p [items, init, e.class]
end
p [1, 2, 3].sum(0.0) { |x| x * 1.5 }, [1, 2].sum { |x| x.to_r / 3 }
