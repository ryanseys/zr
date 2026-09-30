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

# 2-arg Math.log(x, base): a valid base computes log_base(x); a NEGATIVE base
# raises (log of a negative). Per CRuby a base of 0.0 or 1.0 does NOT raise
# (it yields -0.0 / NaN), so only the negative-base domain error is asserted.
puts Math.log(8.0, 2.0)
begin
  Math.log(2.0, -1.0)
  puts "no raise"
rescue Math::DomainError => e
  puts "log neg base: #{e}"
end
