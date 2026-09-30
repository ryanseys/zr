# Enumerable#reduce(init, :op) — explicit init plus a symbol
# operator. The test also checks the 1-arg Symbol form.
puts [1,2,3,4].reduce(:+)
puts [1,2,3,4].reduce(:*)
puts [1,2,3,4].reduce(10, :+)
puts [1,2,3,4].reduce(100, :*)
puts [].reduce(7, :+)
