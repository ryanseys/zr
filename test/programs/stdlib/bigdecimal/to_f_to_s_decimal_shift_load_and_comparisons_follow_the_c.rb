# BigDecimal#to_f overflows and underflows as BigDecimal_to_f does, to_s
# puts the sign mark before a positive infinity and checks its width,
# _decimal_shift checks its value and the exponent's range, _load refuses
# a precision that is not digits, and ==, ===, eql? and <=> compare a
# value of another kind through its own coerce (rb_num_coerce_cmp).
require "bigdecimal"

def try
  value = yield
  p value
rescue => e
  p [e.class, e.message]
end

big = BigDecimal("1#{"0" * 10_000}")
try { [big.to_f, (-big).to_f, BigDecimal("1e309").to_f, BigDecimal("1e-322").to_f] }
try { [BigDecimal("1e-337").to_f, BigDecimal("-1e-337").to_f, BigDecimal("-0").to_f, BigDecimal("2").to_f] }
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, true)
  try { big.to_f }
  try { BigDecimal("1e309").to_f }
end
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, true)
  try { BigDecimal("1e-337").to_f }
  try { BigDecimal("1e-322").to_f }
end

x = BigDecimal("1234.5678")
try { x.to_s(0) }
try { x.to_s(-1) }
try { x.to_s(2.5) }
try { x.to_s(nil) }
try { x.to_s(2**40) }
try { x.to_s("99999999999F") }
try { x.to_s(" 3 F") }
try { [BigDecimal("Infinity").to_s("+"), BigDecimal("Infinity").to_s(" "), BigDecimal("-Infinity").to_s("+")] }
try { [BigDecimal("NaN").to_s("+"), BigDecimal("0").to_s("+"), BigDecimal("-0").to_s(" ")] }

try { [BigDecimal("1.5")._decimal_shift(3), BigDecimal("1.5")._decimal_shift(-3), BigDecimal("1.5")._decimal_shift(2.9)] }
try { BigDecimal("1.5")._decimal_shift("1") }
try { [BigDecimal("-0")._decimal_shift(4), BigDecimal("Infinity")._decimal_shift(1)] }
try { BigDecimal("0.1e9223372036854775800")._decimal_shift(9) }
BigDecimal.save_exception_mode do
  BigDecimal.mode(BigDecimal::EXCEPTION_ALL, true)
  try { BigDecimal("0.1e9223372036854775800")._decimal_shift(9) }
  try { BigDecimal::NAN._decimal_shift(0) }
end

try { BigDecimal._load("18:0.1e1") }
try { BigDecimal._load("-8:0.1e1") }
try { BigDecimal._load("18") }
try { BigDecimal._load(":0.5") }
try { BigDecimal._load("9:x") }
try { BigDecimal._load(5) }
dumped = Marshal.dump(BigDecimal("1", 1))
try { Marshal.load(dumped) }
try { Marshal.load(dumped.gsub(/BigDecimal.*\z/m) { |text| text.gsub(/\d/m, "-") }) }

one = BigDecimal("1")
same = Object.new
def same.coerce(value) = [value, BigDecimal("1")]
none = Object.new
def none.coerce(_) = nil
bad = Object.new
def bad.coerce(_) = 5
try { [one == same, one <=> same, one.eql?(same), one === same, one != same, one <= same] }
try { [one == none, one <=> none] }
try { one == bad }
try { [one == Object.new, one <=> Object.new, one == nil, one == "1"] }
time = Time.at(0)
def time.coerce(value) = [value, value]
try { BigDecimal((2**100).to_s) == time }
