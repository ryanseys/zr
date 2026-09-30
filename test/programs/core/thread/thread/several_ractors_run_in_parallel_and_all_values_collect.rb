r1 = Ractor.new(1) { |n| n * 10 }
r2 = Ractor.new(2) { |n| n * 10 }
r3 = Ractor.new(3) { |n| n * 10 }
puts r1.value + r2.value + r3.value
