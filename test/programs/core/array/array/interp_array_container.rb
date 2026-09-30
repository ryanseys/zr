# String interpolation of typed-array containers.
#
# `#{arr}` gives CRuby's `Array#to_s` shape, the bracketed form
# `[elem, elem, ...]`, for each kind of array.

# Integer array
ints = [1, 2, 3]
puts "ints: #{ints}"

# String array
strs = ["a", "b", "c"]
puts "strs: #{strs}"

# Symbol array
syms = [:x, :y, :z]
puts "syms: #{syms}"

# Float array
floats = [1.5, 2.5, 3.5]
puts "floats: #{floats}"

# mixed array (heterogeneous)
mix = [1, "two", :three, nil]
puts "mix: #{mix}"

# Empty arrays
puts "empty ints: #{[]}"

# Nested arrays
puts "nested: #{[[1, 2], [3, 4]]}"

# nil interpolation (CRuby: empty string, not "0")
n = nil
puts "n: '#{n}'"
