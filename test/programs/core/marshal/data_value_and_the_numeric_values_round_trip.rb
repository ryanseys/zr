# Marshal writes a Data value as the Struct record CRuby writes, reads it
# back frozen, and builds a Rational or a Complex without calling their
# `allocate`, which Ruby cannot call. A class is written by its name
# alone, whatever it holds in its own instance variables.
Point = Data.define(:x, :y)
Pair = Struct.new(:a, :b)

[Point.new(x: 1, y: [2]), Pair.new(3, "four"), 3r, Complex(1, 2), Thread, Point].each do |value|
  dumped = Marshal.dump(value)
  back = Marshal.load(dumped)
  p [dumped, back, back == value, back.frozen?]
end

