# Deep-nested array literals (3D and beyond). `arr[i][j][k]...`
# reads the right Integer at each depth — 3D, 4D, 5D, ... all work.

class T_array_3d_nested_H3
  def initialize
    @t = [[[1, 2, 3], [4, 5, 6]], [[7, 8, 9], [10, 11, 12]]]
  end
  def read(i, j, k); @t[i][j][k]; end
end

h3 = T_array_3d_nested_H3.new
puts h3.read(0, 0, 0)   # 1
puts h3.read(0, 1, 1)   # 5
puts h3.read(1, 0, 2)   # 9
puts h3.read(1, 1, 2)   # 12

# 4D — any depth works.
class T_array_3d_nested_H4
  def initialize
    @t = [[[[1, 2], [3, 4]], [[5, 6], [7, 8]]],
          [[[9, 10], [11, 12]], [[13, 14], [15, 16]]]]
  end
  def read(i, j, k, l); @t[i][j][k][l]; end
end

h4 = T_array_3d_nested_H4.new
puts h4.read(0, 0, 0, 0)   # 1
puts h4.read(0, 1, 0, 1)   # 6
puts h4.read(1, 0, 1, 0)   # 11
puts h4.read(1, 1, 1, 1)   # 16
