# Symbol-keyed hashes: Symbol keys are distinct from String keys.
# Cover both Integer-valued and String-valued shapes — same
# operator surface, different value types — in one file, with
# different local names for the two hashes.

# Int values
hi = {a: 1, b: 2, c: 3}
puts hi[:a]            # 1
puts hi[:b]            # 2
puts hi.length         # 3
puts hi.has_key?(:a)   # true
puts hi.has_key?(:z)   # false
puts hi.empty?         # false
hi[:d] = 4
puts hi[:d]            # 4
puts hi.length         # 4

# String values
hs = {name: "Alice", role: "admin"}
puts hs[:name]              # Alice
puts hs[:role]              # admin
puts hs.length              # 2
puts hs.has_key?(:name)     # true
puts hs.has_key?(:unknown)  # false
hs[:email] = "a@b.c"
puts hs[:email]             # a@b.c
puts hs.length              # 3
