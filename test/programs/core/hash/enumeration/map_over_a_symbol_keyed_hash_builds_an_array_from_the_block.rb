# Hash#map with a block on a hash of Symbol keys and Integer values
# gives an Array of the block's values.
h = {a: 1, b: 2}
puts h.map { |k, v| v * 10 }.inspect
puts h.map { |k, v| "#{k}=#{v}" }.inspect
