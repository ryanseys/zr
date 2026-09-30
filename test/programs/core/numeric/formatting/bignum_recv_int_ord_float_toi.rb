# Bignum-receiver conveniences (digits/to_s(base)/even?/odd?/abs),
# Integer#ord/#integer?, and Float#to_i beyond int64, which gives a Bignum
# and does not raise RangeError.
x = 2 ** 100
p(x.digits)
p(x.to_s(16))
p(x.even?)
p(x.odd?)
p(x.abs)
y = x * -1
p(y.abs)
p(x.to_s(2).length)
p(5.integer?)
p(65.ord)
n = 7
p n.ord
p n.integer?
begin
  (1.5e20).to_i
rescue RangeError => e
  puts "RangeError"
end
p 3.9.to_i
p(-2.9.to_i)
