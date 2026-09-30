# Struct#initialize by position: fewer values leave nil, more raise,
# keywords bind by name, and each keyword_init: form keeps its rule.
P = Struct.new(:a, :b, :c)
p P.new.to_a
p P.new(1).to_a
p P.new(1, 2, 3).to_a
begin
  P.new(1, 2, 3, 4)
rescue ArgumentError => e
  p e.message
end
p P.new(a: 1, c: 3).to_a
p P.new(1, b: 2).to_a
begin
  P.new(d: 1)
rescue ArgumentError => e
  p e.message
end
K = Struct.new(:a, :b, keyword_init: true)
p K.new(a: 1).to_a
p K.new.to_a
begin
  K.new(1)
rescue ArgumentError => e
  p e.message
end
F = Struct.new(:a, :b, keyword_init: false)
p F.new(a: 1).to_a
p P[4, 5].to_a
o = P.new(1, 2, 3)
o.send(:initialize, 7)
p o.to_a
