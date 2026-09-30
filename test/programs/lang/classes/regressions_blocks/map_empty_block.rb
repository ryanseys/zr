# An empty `map {}` block still gives an array of the same length as
# the receiver, with nil in each element. This is true for each kind
# of receiver.

# Range#map
puts (0..2).map {}.length          # 3

# N.times.map
puts 4.times.map {}.length         # 4

# Integer Array#map
puts [10, 20, 30].map {}.length    # 3

# String Array#map
puts ["a", "b", "c", "d"].map {}.length   # 4

# mixed Array#map
puts [1, "two", :three].map {}.length     # 3

# Array#map on objects of one user class
class T_map_empty_block_Box
  def initialize(v); @v = v; end
end
puts [T_map_empty_block_Box.new(1), T_map_empty_block_Box.new(2), T_map_empty_block_Box.new(3)].map {}.length  # 3
