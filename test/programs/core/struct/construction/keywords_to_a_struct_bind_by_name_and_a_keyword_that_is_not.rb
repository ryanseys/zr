# Keywords bind by name where the class takes them: every member,
# some members, none, and a keyword that is not a member.
K = Struct.new(:a, :b, :c, keyword_init: true)
p K.new(a: 1, b: 2, c: 3).to_a
p K.new(c: 3).to_a
p K.new(**{}).to_a
h = { b: 5 }
p K.new(**h).to_a
begin
  K.new(a: 1, z: 2)
rescue ArgumentError => e
  p e.message
end
N = Struct.new(:a, :b)
p N.new(b: 2).to_a
begin
  N.new(a: 1, zz: 2)
rescue ArgumentError => e
  p e.message
end
F = Struct.new(:a, :b, keyword_init: false)
p F.new(a: 1, b: 2).to_a
class Sub < K
  def with(**over) = Sub.new(**to_h, **over)
end
p Sub.new(a: 1).with(b: 7).to_a
