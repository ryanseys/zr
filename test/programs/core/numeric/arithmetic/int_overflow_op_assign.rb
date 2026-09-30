# Every integer operator that overflows 64 bits gives a Bignum, as in CRuby,
# in the binary form and in the op-assign form (`x *= y`, +=, <<=, **=).
# So `1 << 63` and a runtime `a ** 64` print their exact values.
def try
  yield
rescue RangeError => e
  puts "RangeError: #{e.message}"
end

a = 999_999_999_999
try { a *= 999_999_999_999 }
b = 10
try { b += 9_223_372_036_854_775_800 }

c = 1
try { puts c << 63 }
try { puts c << 64 }
puts c << 62
d = 1
try { d <<= 63 }
puts d

pw = 2
try { puts pw ** 64 }
puts pw ** 62
f = 5
f **= 3
puts f

# op-assign division uses Ruby's floored semantics
g = -7
g /= 2
puts g
h = -7
h %= 3
puts h

# ivar op-assign works the same way
class Acc
  attr_reader :n
  def initialize = (@n = 999_999_999_999)
  def blow = (@n *= 999_999_999_999)
end
acc = Acc.new
begin
  acc.blow
rescue RangeError => e
  puts "ivar RangeError: #{e.message}"
end
