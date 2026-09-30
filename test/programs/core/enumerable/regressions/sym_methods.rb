# Symbol methods
puts :hello.to_s        # hello
puts :hello.length      # 5
puts :hello.empty?      # false
puts (:a == :a)         # true
puts (:a == :b)         # false
puts (:a != :b)         # true

# String#to_sym → Symbol
s = "dynamic".to_sym
puts s                  # dynamic

# to_sym on literal (compile-time interned)
t = "hello".to_sym
puts t                  # hello

# Symbol#to_sym is identity
puts :foo.to_sym        # foo

# Symbol#<=> (lexical)
puts (:apple <=> :banana)  # -1
puts (:banana <=> :apple)  # 1
puts (:apple <=> :apple)   # 0

# Kernel#p with symbol
p :hello                # :hello
