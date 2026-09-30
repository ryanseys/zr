# reduce with a Symbol accumulator whose block value is read from a nested Hash
# (of mixed value types): the block value becomes the next accumulator.
T = { a: { "0" => :a, "1" => :b }, b: { "0" => :a, "1" => :b } }
p "01".chars.reduce(:a) { |s, c| T[s][c] }
p "10".chars.reduce(:a) { |s, c| T[s][c] }
