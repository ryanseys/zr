# Math.* methods raise Math::DomainError on out-of-domain input, as
# in CRuby. Math::DomainError < StandardError < Exception, so the
# natural CRuby idiom works:
#
#   x = Math.sqrt(input) rescue 0.0
#   begin Math.log(x); rescue Math::DomainError => e; ...; end
#
# Methods with restricted domains (sqrt, log, log2, log10, acos,
# asin, acosh, atanh, plus Integer.sqrt) can raise. Unrestricted
# methods (cos, sin, tan, atan, sinh, cosh, tanh, asinh, exp,
# atan2, hypot) do not raise.

# Unrestricted methods don't raise — return NaN/Infinity per IEEE 754
puts Math.cos(0.0)
puts Math.exp(1.0).round(4)

