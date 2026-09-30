# Hash#dup on a hash with String values, with String keys and with
# Integer keys. `.length`, `[]=` and `.each` work on the copy, and
# the copy is independent of the original.

# String keys, String values
h1 = {"a" => "1", "b" => "2"}
m1 = h1.dup
m1["c"] = "3"
puts h1.length          # 2
puts m1.length          # 3
puts m1["a"]            # 1
puts m1["c"]            # 3

# Integer keys, String values
h2 = {1 => "one", 2 => "two"}
m2 = h2.dup
m2[3] = "three"
puts h2.length          # 2
puts m2.length          # 3
puts m2[1]              # one
puts m2[3]              # three

# Verify the dup is independent (original unchanged).
puts h1.has_key?("c")   # false
puts h2.has_key?(3)     # false
