# Integer#step with a block in expression position — CRuby returns
# the receiver, not 0.
result = 1.step(5) { |x| x }
puts result.inspect
puts result.class
