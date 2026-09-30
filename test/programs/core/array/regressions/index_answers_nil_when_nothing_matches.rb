# `Array#index(x)` / `#find_index(x)` / `#rindex(x)` return
# Integer or nil in CRuby. They give nil when no element matches,
# not -1. `.nil?` and `== nil` see that nil.

# Int arrays
ints = [10, 20, 30, 40]
puts ints.index(20).inspect       # 1
puts ints.index(999).inspect      # nil
puts ints.index(999).nil?         # true
puts ints.index(20).nil?          # false
puts ints.find_index(30).inspect  # 2

# String arrays
strs = ["alpha", "beta", "gamma"]
puts strs.index("beta").inspect   # 1
puts strs.index("zeta").inspect   # nil
puts strs.rindex("alpha").inspect # 0
puts strs.rindex("zeta").inspect  # nil
