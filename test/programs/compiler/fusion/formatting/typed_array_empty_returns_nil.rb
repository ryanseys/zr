# pop/shift/min/max on an empty Array of Integers return nil per
# MRI. Non-empty returns the value.
a = [1, 2]
2.times { a.pop }
puts "empty int pop: " + a.pop.inspect

b = [1, 2]
2.times { b.shift }
puts "empty int shift: " + b.shift.inspect

puts "empty int min: " + [].min.inspect
puts "empty int max: " + [].max.inspect

# Non-empty still works.
puts [1, 2, 3].pop
puts [1, 2, 3].shift
puts [3, 1, 2].min
puts [3, 1, 2].max
