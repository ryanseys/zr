# Ruby semantic requirements that Phase 2 satisfies

# 0. Symbol is distinct from String
puts :a == "a"            # false
puts "a" == :a            # false
puts :a != "a"            # true

# 1. Same symbol is equal to itself
puts :foo == :foo         # true

# 2. Different symbols are not equal
puts :foo == :bar         # false

# 3. Symbol-keyed hash distinguishes sym keys (Ruby semantics)
h = {a: 1, b: 2}
puts h.has_key?(:a)       # true
puts h.has_key?(:z)       # false
puts h.has_key?("a")      # false - sym key hash, string arg

# 3b. {a:1}[:a] finds it
puts h[:a]                # 1

# 4. to_sym idempotent on Symbol
puts :foo.to_sym == :foo  # true

# 5. String#to_sym + Symbol#to_s round trip
puts "hello".to_sym.to_s  # hello

# 6. Interned symbol identity ("foo" interns to same ID as :foo)
puts "foo".to_sym == :foo # true
