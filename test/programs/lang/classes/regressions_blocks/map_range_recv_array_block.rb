# `Range#map { array_block }` gives an Array of Arrays, not a Range.
# So the result can be indexed `arr[i][j]` directly. A second ivar
# holds a plain Integer Array.

class T_map_range_recv_array_block_C
  def initialize
    # Block returns an Integer Array — outer is an Array of Arrays.
    @rows = (0...3).map { |i| [i, i * 10] }
    # Separate ivar for a plain Integer Array.
    @flat = [10, 20, 30]
  end

  def show
    @rows.each { |row| row.each { |v| puts v } }
    @flat.each { |v| puts v }
  end
end

T_map_range_recv_array_block_C.new.show
# Expected:
#   0 / 0 / 1 / 10 / 2 / 20 (each row's elements)
#   10 / 20 / 30 (flat)
