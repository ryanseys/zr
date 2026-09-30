# `(a..b).step(k)` without a block returns the stepped values, and
# `.to_a` gives them as an Array.

puts (1..10).step(3).to_a.inspect
puts (0..20).step(5).to_a.inspect

# Inclusive vs exclusive end:
puts (1...10).step(3).to_a.inspect

# step larger than range -> single element.
puts (1..10).step(100).to_a.inspect

# step exactly hits the end.
puts (1..10).step(1).to_a.inspect
