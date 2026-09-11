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

__END__
["\x04\bS:\nPoint\a:\x06xi\x06:\x06y[\x06i\a", #<data Point x=1, y=[2]>, true, true]
["\x04\bS:\tPair\a:\x06ai\b:\x06bI\"\tfour\x06:\x06ET", #<struct Pair a=3, b="four">, true, false]
["\x04\bU:\rRational[\ai\bi\x06", (3/1), true, true]
["\x04\bU:\fComplex[\ai\x06i\a", (1+2i), true, true]
["\x04\bc\vThread", Thread, true, false]
["\x04\bc\nPoint", Point, true, false]
