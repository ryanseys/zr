# The exception modes raise at a parse and at a result, each with
# VpException's words, and mode and round check their arguments.
require "bigdecimal"
zero, inf, nan = BigDecimal("0"), BigDecimal("Infinity"), BigDecimal("NaN")
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
  [-> { BigDecimal("NaN") }, -> { zero / zero }, -> { inf - inf }, -> { nan + 1 }].each { |c| p((c.call rescue $!)) }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
  [-> { BigDecimal("-Infinity") }, -> { inf * 2 }, -> { BigDecimal("1") / 0 }].each { |c| p((c.call rescue $!)) }
end
p((BigDecimal.mode(BigDecimal::EXCEPTION_NaN, 1) rescue $!), (BigDecimal.mode(BigDecimal::ROUND_MODE, :bogus) rescue $!),
  (BigDecimal.mode(BigDecimal::ROUND_MODE, "bogus") rescue $!))
one = BigDecimal("1")
p((one.round(half: :bogus) rescue $!), (one.round(nil) rescue $!), (one.round(1, :bogus) rescue $!), one.round(half: nil))
p [BigDecimal("1.5")._dump, BigDecimal("1.23456789012345678901")._dump, (BigDecimal("1") / 3)._dump, BigDecimal("1e20")._dump]
p Marshal.dump(BigDecimal("1.5")).bytesize, BigDecimal.singleton_methods(false).sort, BigDecimal.private_instance_methods(false)
