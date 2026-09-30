# Hash.new with a block whose body assigns a default: an empty `[]`/`{}`
# container, or an Integer. The block stores the default under the key.
# (The example uses String/Integer keys so that #inspect matches CRuby.)

# array default
words = Hash.new { |h, k| h[k] = [] }
words["a"] << 1
words["a"] << 2
words["b"] << 3
p words

# integer default
counts = Hash.new { |h, k| h[k] = 0 }
counts["x"] += 1
counts["x"] += 1
counts["y"] += 5
p counts

# hash default (nested)
nested = Hash.new { |h, k| h[k] = {} }
nested["a"]["b"] = 1
nested["a"]["c"] = 2
p nested

# the block value is returned (auto-vivification returns the new container)
fresh = Hash.new { |h, k| h[k] = [] }
fresh["z"].push(9)
p fresh["z"]
