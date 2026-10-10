x = 1
@iv = 2
$gv = 3
class K
  @@cv = 4
  def m = defined?(@@cv)
  def n = defined?(super)
  def o = defined?(yield)
  def p2 = defined?(@nope)
end
class L < K
  def m = [defined?(super), super]
end
p defined?(x), defined?(y), defined?(@iv), defined?(@nope), defined?($gv), defined?($nope)
p defined?(String), defined?(Nope), defined?(K::Nope), defined?(puts), defined?(nope_method), defined?(x.to_s), defined?(x.nope)
p defined?(self), defined?(nil), defined?(true), defined?(x = 2), defined?(@a = 1), defined?(1 + 1), defined?(yield), defined?(super)
p K.new.m, K.new.n, K.new.o, K.new.o { }, K.new.p2, L.new.m
p defined?(nope.bar), defined?(Nope::X), defined?(x.to_s.nope), defined?(::String), defined?(K::X)
