# `Range#map` / `Array#map` whose block returns an array
# (1D, 2D, 3D nested). `arr[i][j][k]...` reads the right value at
# each depth. Optcarrot builds a table this way:
# `TILE_LUT = [...].map { (0..7).map { (0...0x10000).map { ... }
# }.transpose }`.

# Range#map -> an Array of Integer Arrays (2D)
class T_map_block_returns_nested_array_M2
  def initialize
    @t = (0..2).map { |i| (0..3).map { |j| i * 10 + j } }
  end
  def read(i, j); @t[i][j]; end
end
m2 = T_map_block_returns_nested_array_M2.new
puts m2.read(0, 0)   # 0
puts m2.read(1, 2)   # 12
puts m2.read(2, 3)   # 23

# Integer Array map { Range#map { ... } } -> 3D
class T_map_block_returns_nested_array_M3
  def initialize
    @t = [10, 20].map do |a|
      (0..2).map { |b| [a + b, a + b + 100] }
    end
  end
  def read(i, j, k); @t[i][j][k]; end
end
m3 = T_map_block_returns_nested_array_M3.new
puts m3.read(0, 0, 0)   # 10
puts m3.read(0, 1, 1)   # 111
puts m3.read(1, 2, 0)   # 22
puts m3.read(1, 2, 1)   # 122
