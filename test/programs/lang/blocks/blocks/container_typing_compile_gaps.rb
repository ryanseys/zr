# Three shapes that did not compile at all, each for its own reason.

# A multiple-assignment target captured by a later block. The target lives in a
# heap cell, and the assignment named `lv_<name>` -- a variable that was never
# declared, with the cell sitting right beside it in the same function.
def build
  [1, ["a", "b"], "tail"]
end

n, list, tail = build

list.each do |s|
  p [n, s, tail]
end

# A parameter defaulting to an empty `{}`, with no key evidence at the call
# site. The body writes String keys into it, and they stay Strings.
def flat(node, acc = {})
  node.each { |key, value| acc[key.to_s] = value }
  acc
end

p flat({ "a" => 1 })
p flat({ "b" => 2, "c" => 3 })

# A defaulted accumulator whose key is already right stays as it is
def tally(words, acc = {})
  words.each { |w| acc[w] = (acc[w] || 0) + 1 }
  acc
end

p tally(["x", "y", "x"])

# Hash#select / #reject whose block value is only known at run time -- here the
# block calls a Proc held as the hash value. The predicate was emitted as
# `!(value)`, and a boxed value is a struct, which does not compile.
checks = { "big" => ->(v) { v > 1 }, "small" => ->(v) { v < 1 } }
p checks.reject { |_k, check| check.call(3) }.keys
p checks.select { |_k, check| check.call(3) }.keys

# the same predicate with an ordinary boolean block still works
nums = { "a" => 1, "b" => 5 }
p nums.select { |_k, v| v > 2 }.keys
p nums.reject { |_k, v| v > 2 }.keys
