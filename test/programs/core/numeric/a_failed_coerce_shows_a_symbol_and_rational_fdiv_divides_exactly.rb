# A coerce that fails shows nil, true, false or a Symbol by inspect and
# any other value by its class. Rational#fdiv divides exactly, then
# makes a Float, so a bad operand fails to coerce into Rational.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

[:a, nil, true, false, "s", Object, [1]].each do |x|
  show("7.remainder(#{x.inspect})") { 7.remainder(x) }
  show("(2**70).remainder(#{x.inspect})") { (2**70).remainder(x) }
  show("2.5.remainder(#{x.inspect})") { 2.5.remainder(x) }
  show("(3/4r).remainder(#{x.inspect})") { (3r / 4).remainder(x) }
  show("(3/4r).fdiv(#{x.inspect})") { (3r / 4).fdiv(x) }
end

show("fdiv") do
  [(3r / 4).fdiv(7), (1r / 3).fdiv(3), (3r / 4).fdiv(0), (3r / 4).fdiv(0.0), (3r / 4).fdiv(1),
   (3r / 4).fdiv(2.5), (3r / 4).fdiv(1r / 3), (-3r / 4).fdiv(0), (2r**70).fdiv(3), (1r / 7).fdiv(1r / 7)]
end
show("fdiv complex") { (3r / 4).fdiv(Complex(1, 1)) }
show("fdiv exact") { (1r / 3).fdiv(10**30) }
