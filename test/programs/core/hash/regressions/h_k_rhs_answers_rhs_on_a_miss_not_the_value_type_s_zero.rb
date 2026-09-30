# `hash[k] || rhs` returns rhs when the key is missing, because the
# lookup gives nil. It must not give the value type's zero (0 / ""):
# 0 / "" are truthy in Ruby, so `||` would not use the fallback.

# Empty hash, no writes.
h1 = {}
puts (h1[:missing] || "fallback")

# String-valued hash via prior write.
h2 = {}
h2[:set_key] = "value"
puts (h2[:missing] || "fallback")

# Int-valued hash via prior write -- the fallback wins, not 0.
h3 = {}
h3[:set] = 1
puts (h3[:missing] || -1)

# Present key returns the value, not the fallback.
h4 = {}
h4[:found] = "got it"
puts (h4[:found] || "fallback")
