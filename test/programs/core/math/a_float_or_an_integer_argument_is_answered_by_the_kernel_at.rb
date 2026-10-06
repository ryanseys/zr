# Math.sqrt, sin, cos, tan, atan, exp and cbrt answer a Float or a
# fixnum with no send of the check: the domain refusal, -0.0, an
# integer past 2**53, a negative integer and a bignum answer as
# ruby does, and a redefinition of the function is what runs.
p Math.sqrt(-0.0), Math.sqrt(0), Math.sqrt(1 << 62), Math.sqrt(9223372036854775807), Math.sqrt(Float::MAX), Math.sqrt(Float::INFINITY), Math.sqrt(Float::NAN).nan?
p Math.sin(1 << 61), Math.exp(-1000), Math.cbrt(-8), Math.tan(1), Math.atan(1).round(6), Math.cos(0)
p (Math.sqrt(-1.5) rescue $!.message), (Math.sqrt(-(1 << 62)) rescue $!.message), (Math.sin("1") rescue $!.message), (Math.exp(Rational(1, 2)) rescue $!.message).round(6)
module Math
  remove_method :sqrt
  def self.sqrt(x) = :mine
end
p Math.sqrt(4)
