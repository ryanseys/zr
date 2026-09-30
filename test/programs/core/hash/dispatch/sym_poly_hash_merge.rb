# `Hash#merge` on a Symbol-keyed hash with heterogeneous values
# (Symbol => {Integer | String | Boolean | nil}). A non-mutating
# `merge` answers a new hash with all the keys.
#
# The `[]` case covers a local that can hold values of more than one
# type (e.g. because of an `is_a?` branch), while the value at run
# time is such a hash.

DEFAULTS = { a: 1, b: "two", c: true, d: nil, e: 16 }

# 1. Non-mutating merge: result has overrides from b, other keys
#    preserved from a.
m = DEFAULTS.merge({ a: 99, b: "TWO" })
puts m[:a]              # 99 (overridden)
puts m[:b]              # TWO
puts m[:c]              # true (preserved)
puts m[:e]              # 16

# 2. Original receiver is unchanged.
puts DEFAULTS[:a]       # 1

# 3. Symbol-key `[]` lookup on a local that can hold more than one
#    type. The is_a?(String) branch puts a Hash in `opt`, and the
#    reads of `merged[:k]` answer the merged values.
def lookup(opt)
  # Mixed-value override hash for the `is_a?(String)` branch (and the
  # explicit-Hash call site too).
  opt = { a: 7, c: false } if opt.is_a?(String)
  merged = DEFAULTS.merge(opt)
  return merged[:a], merged[:b], merged[:e]
end

a, b, e = lookup("string-input")
puts a                  # 7  (from the boxed hash inside the if branch)
puts b                  # two
puts e                  # 16

a, b, e = lookup({ a: 100, b: "B", e: 99 })
puts a                  # 100
puts b                  # B
puts e                  # 99
