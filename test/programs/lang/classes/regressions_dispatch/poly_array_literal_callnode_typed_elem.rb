# `[A, B]` outer literal where A and B are calls (not Array literals)
# that return an Array of Arrays (e.g. `(0..N).map { ... }`).
# `arr[b][i][j]` reads the right Integer at each level, and `length`
# works at each level.

class T_poly_array_literal_callnode_typed_elem_C
  def initialize
    @a = [(0..3).map { |i| [i * 10, i * 10 + 1, i * 10 + 2] },
          (0..3).map { |i| [i * 100, i * 100 + 1, i * 100 + 2] }]
  end
  def get(b, i, j); @a[b][i][j]; end
  def out_len; @a.length; end
  def mid_len(b); @a[b].length; end
  def in_len(b, i); @a[b][i].length; end
end

c = T_poly_array_literal_callnode_typed_elem_C.new
puts c.out_len           # 2
puts c.mid_len(0)        # 4
puts c.in_len(0, 0)      # 3
puts c.get(0, 0, 0)      # 0
puts c.get(0, 1, 1)      # 11
puts c.get(0, 3, 2)      # 32
puts c.get(1, 0, 0)      # 0
puts c.get(1, 2, 1)      # 201
puts c.get(1, 3, 2)      # 302
