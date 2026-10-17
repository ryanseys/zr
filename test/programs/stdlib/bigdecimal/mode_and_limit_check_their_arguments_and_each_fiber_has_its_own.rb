# BigDecimal.mode and BigDecimal.limit check their arguments as the C
# does, and keep each setting in the current fiber's locals, under the
# C's names: another thread or fiber starts from the defaults.
require "bigdecimal"

def try
  p yield
rescue => e
  p [e.class, e.message]
end

try { BigDecimal.mode(BigDecimal::EXCEPTION_ALL, 1) }
try { BigDecimal.mode(BigDecimal::ROUND_MODE, 256) }
try { BigDecimal.mode(BigDecimal::ROUND_MODE, :xyzzy) }
try { BigDecimal.mode(0xf000, true) }
try { BigDecimal.mode(0xf000) }
try { BigDecimal.mode("1") }
try { BigDecimal.mode(BigDecimal::ROUND_MODE, :banker) }
try { BigDecimal.mode(BigDecimal::ROUND_MODE) }
try { BigDecimal.mode(BigDecimal::EXCEPTION_NaN | BigDecimal::EXCEPTION_ZERODIVIDE, true) }
try { BigDecimal.mode(BigDecimal::EXCEPTION_ALL) }
try { BigDecimal.mode(BigDecimal::EXCEPTION_ALL, false) }
try { BigDecimal.limit(-1) }
try { BigDecimal.limit(3) }
try { BigDecimal.limit(nil) }
try { BigDecimal.limit }
try { BigDecimal.limit(2.9) }
try { BigDecimal.limit("2") }
try { BigDecimal("1") / 3 }
try { BigDecimal.limit(0) }

BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_UP)
BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
BigDecimal.limit(5)
Thread.new do
  p [BigDecimal.mode(BigDecimal::ROUND_MODE), BigDecimal.mode(BigDecimal::EXCEPTION_ALL), BigDecimal.limit]
  BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
  p BigDecimal.mode(BigDecimal::ROUND_MODE)
end.join
p Fiber.new { [BigDecimal.mode(BigDecimal::ROUND_MODE), BigDecimal.limit] }.resume
p [BigDecimal.mode(BigDecimal::ROUND_MODE), BigDecimal.mode(BigDecimal::EXCEPTION_ALL), BigDecimal.limit]
p Thread.current.keys.grep(/BigDecimal/).sort

p BigDecimal.save_rounding_mode { BigDecimal.mode(BigDecimal::ROUND_MODE, :floor); :inside }
p BigDecimal.mode(BigDecimal::ROUND_MODE)
BigDecimal.save_exception_mode { BigDecimal.mode(BigDecimal::EXCEPTION_ALL, true) }
p BigDecimal.mode(BigDecimal::EXCEPTION_ALL)
BigDecimal.save_limit { BigDecimal.limit(1) }
p BigDecimal.limit
