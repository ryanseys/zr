# `Math.f(x)` for sqrt, cbrt, sin, cos, tan, atan and exp calls the
# kernel's fast path at the site while the constant is Math and its
# functions are the core's. It must give what the method gives: Float
# and Integer arguments, a Bignum, the DomainError and TypeError of the
# method, a Rational through the send, another constant named Math in
# a nested scope, and a later redefinition.
p Math.sqrt(16), Math.sqrt(2.0), Math.sin(0), Math.cos(0.0), Math.exp(1), Math.atan(1.0), Math.cbrt(27), Math.tan(0.5)
p Math.sqrt(10**30)
begin
  Math.sqrt(-1)
rescue Math::DomainError => e
  p e.message
end
begin
  Math.sin("x")
rescue TypeError => e
  p e.message
end
p Math.sin(Rational(1, 2))
module Foo
  Math = Object.new
  def Math.sin(x) = :fake
  def self.t = Math.sin(1.0)
end
p Foo.t
def Math.cos(x) = :redefined
p Math.cos(0.0), Math.sin(0.0)
