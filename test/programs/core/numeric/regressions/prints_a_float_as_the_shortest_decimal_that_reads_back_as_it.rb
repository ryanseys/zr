# Shortest decimal that round-trips; fixed-point inside CRuby's
# [-4, 15] decimal-exponent window, scientific (`d.ddde+NN`)
# outside.
puts 1.0
puts 100.0
puts(-3.25)
puts 1234567890.0
puts 1234567890.5
puts 0.1
puts 0.3
puts 0.30000000000000004
puts 0.0001
puts 0.00001
puts 1.5e14
puts 1.0e15
puts 9.99e15
puts 1.0e16
puts 1.0e100
puts(-0.0)
puts Float::INFINITY
puts(-Float::INFINITY)
puts Float::NAN
p 1.0
p 1234567890.5
p 1.0e16
p(-0.0)
