# `Hash.new(default_value)` per-instance default support.
#
# A lookup of a missing key returns the default. `Hash#default` and
# `Hash#default=` read and change it. `dup` and `merge` keep the
# default (merge keeps the LEFT receiver's default, as in CRuby).
#
# This example does not test the block form `Hash.new { |h, k| ... }`.

# Int default
h = Hash.new(5)
puts h[:a]              # 5
puts h["x"]             # 5
puts h.length           # 0
puts h.key?(:a)         # false
puts h.default          # 5

# Modify default; existing key unaffected
h.default = 99
puts h["missing"]       # 99
h["b"] = 10
puts h["b"]             # 10
puts h["c"]             # 99

# String default
s = Hash.new("none")
puts s["x"]             # none
puts s.default          # none

# dup propagates default
h2 = Hash.new(42)
h2["a"] = 1
d = h2.dup
puts d.default          # 42
puts d["never_set"]     # 42
puts d.length           # 1
puts d["a"]             # 1

# merge inherits left default
m = h2.merge({"x" => 100})
puts m.default          # 42
puts m["not_there"]     # 42

# Hash.new(0) -- a counter, as lrama uses it.
counter = Hash.new(0)
counter["x"] = counter["x"] + 1
puts counter["x"]       # 1
puts counter["z"]       # 0

# Float default with int keys.
f = Hash.new(0.0)
f[1] += 2.5
p f[1]                  # 2.5
p f[7]                  # 0.0 (default for a missing key)
p f.default             # 0.0
f.default = 1.5
p f[9]                  # 1.5
fd = f.dup
p fd[42]                # 1.5 (dup propagates default)
fm = f.merge({2 => 3.5})
p fm[2]                 # 3.5
p fm[99]                # 1.5 (merge inherits left default)
