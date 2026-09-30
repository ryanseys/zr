# A block can capture a local and assign a new value to it. This example does
# that with a Range, a Rational, a Complex and a Float range. It also captures
# a class, and it reads captured values that the block does not change.

2.times do |n|
  v = (n..3)
  pr = proc { v = (n..4); nil }
  pr.call
  puts v.to_s
end

2.times do |n|
  v = Rational(n + 1, 2)
  pr = proc { v = Rational(n + 1, 3); nil }
  pr.call
  puts v.to_s
end

2.times do |n|
  v = Complex(n, 1)
  pr = proc { v = Complex(n, 2); nil }
  pr.call
  puts v.to_s
end

2.times do |n|
  v = (n + 0.5)..3.5
  pr = proc { v = (n + 0.5)..4.5; nil }
  pr.call
  puts v.to_s
end

# a captured class, new on each iteration
2.times do |n|
  k = Struct.new(:x)
  pr = proc { k.new(n) }
  puts pr.call.x.to_s
end

# reading a captured by-value struct without reassigning it
2.times do |n|
  span = (n..(n + 2))
  rat = Rational(n + 1, 4)
  pr = proc { span.to_a.length + rat.denominator }
  puts pr.call.to_s
end
