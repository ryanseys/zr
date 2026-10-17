# BigDecimal_DoDivmod: div, %, remainder and divmod take the exact
# quotient (floored, or truncated for remainder) and the exact rest,
# whatever BigDecimal.limit says, with the C's answers for zeros,
# infinities and NaN. `/` rounds once, to its width capped by the limit,
# and the forms that take a precision accept only values that become a
# BigDecimal.
require "bigdecimal"

def try
  value = yield
  p value
rescue => e
  p [e.class, e.message]
end

x = BigDecimal(-(9**100))
y = BigDecimal(7**100)
BigDecimal.save_limit do
  BigDecimal.limit(3)
  try { x.div(y) }
  try { x.modulo(y) }
  try { x.remainder(y) }
  try { x.divmod(y) }
  try { BigDecimal("0.8888") / BigDecimal("3") }
  try { BigDecimal("0.8888").div(BigDecimal("3"), 5) }
  try { BigDecimal("0.8888").quo(BigDecimal("3"), 5) }
  try { BigDecimal("0.8888").quo(BigDecimal("3")) }
  try { BigDecimal.limit }
end

a = BigDecimal("3e100")
b = BigDecimal("-1.7e-100")
try { q, r = a.divmod(b); [q.to_s.length, r, a - (q * b) == r] }
try { BigDecimal("199.9999999999999999999999999").divmod(1) }
try { BigDecimal("2e55").divmod(BigDecimal("-1.23456789e10")) }
try { [BigDecimal("7").divmod(2), BigDecimal("-7").divmod(2), BigDecimal("7").divmod(-2), BigDecimal("-7").divmod(-2)] }
try { [BigDecimal("-7").remainder(2), BigDecimal("7").remainder(-2), BigDecimal("-6") % 3, BigDecimal("6").remainder(-3)] }

[-0.0, 0.0].each do |left|
  [-1.0, 1.0].each do |right|
    a = BigDecimal(left)
    b = BigDecimal(right)
    try { [a.remainder(b).to_s, a.modulo(b).to_s, a.divmod(b).map { BigDecimal(it) }.inspect] }
  end
end

inf = BigDecimal("Infinity")
nan = BigDecimal("NaN")
try { [BigDecimal(1).divmod(inf), BigDecimal(-1).divmod(inf), BigDecimal(-1).remainder(inf), BigDecimal(1) % -inf] }
try { (inf % 2).nan? }
try { inf.divmod(2) }
try { nan.divmod(2) }
try { BigDecimal(1).div(nan) }
try { BigDecimal(1) % 0 }
try { BigDecimal(1).divmod(BigDecimal(0)) }
try { BigDecimal(1).div(0) }

try { BigDecimal(1).div(3, nil) }
try { BigDecimal(1).div(3, -1) }
try { BigDecimal(1).div(3, "2") }
try { BigDecimal(1).quo(3, -2) }
try { BigDecimal(1).add(1, 2**70) }
try { BigDecimal(1).add(1, 2.9) }
try { BigDecimal(1).div(Object.new, 2) }
try { BigDecimal(1).mult(Object.new, 2) }
try { BigDecimal(1).add(Object.new, 2) }
try { BigDecimal(1) + Object.new }
try { BigDecimal(3) / Rational(1, 3) }
try { BigDecimal(3).div(Rational(1, 7), 40) }
try { BigDecimal("1.5") % Rational(1, 3) }

tiny = BigDecimal("0.1e#{(-(((2**63) - 8) / 9) * 9) - 8}")
try { tiny / 10 }
try { BigDecimal(2) / 3 }
