# `Hash#merge` on a String-keyed hash with mixed value types.
#
# Coverage:
#   - mixed-value seed + Integer-valued override.
#   - mixed-value seed + String-valued override.
#   - mixed-value seed + mixed-value override.
#
# This test does not cover an argument whose Hash kind is only
# known at run time.

h = { "a" => 1, "b" => "two" }  # mixed values
m = h.merge({ "c" => 3 })       # Integer-valued arg
puts m.length                    # 3
puts m["a"] == 1 ? "a-ok" : "a-bad"
puts m["c"] == 3 ? "c-ok" : "c-bad"

# String-valued override of a mixed-value recv.
h2 = { "x" => 1, "y" => "two" }
m2 = h2.merge({ "z" => "three" })
puts m2.length                   # 3
puts m2["z"] == "three" ? "z-ok" : "z-bad"

# mixed-value override of a mixed-value recv.
h3 = { "p" => 1, "q" => "two" }
extra = { "r" => 3, "s" => "four" }
m3 = h3.merge(extra)
puts m3.length                   # 4
