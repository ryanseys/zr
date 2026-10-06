S = Struct.new(:a, :b)
s = S.new(1, 2)
p s.values_at(0..3), s.values_at(-1, 0)
[-> { s.values_at(5) }, -> { s.values_at(-3) }, -> { s.values_at(-3..-1) }].each do |f|
  f.call
rescue IndexError, RangeError => e
  p [e.class, e.message]
end
