# Float#step yields floats, so a step of 0.5 does not truncate
# to 0.
result = []
1.0.step(3.0, 0.5) { |x| result << x }
puts result.inspect

# int step still works
out = []
1.step(7, 2) { |i| out << i }
puts out.inspect

# float step argument widens int recv to float
result2 = []
1.step(3.0, 0.5) { |x| result2 << x }
puts result2.inspect
