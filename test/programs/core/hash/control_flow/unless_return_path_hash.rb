# `unless cond; return {hash}; end; nil` returns either the hash from
# the unless body or the trailing nil. Both values are possible results.

def self.outer(flag)
  unless flag
    return { x: "y" }
  end
  nil
end

puts outer(false).nil? ? "nil" : "found"
puts outer(true).nil? ? "nil" : "found"

# `unless cond` with else_clause — both arms can carry returns.
def self.classify(n)
  unless n.zero?
    return { kind: "nonzero" }
  else
    return { kind: "zero" }
  end
end

puts classify(0)[:kind]
puts classify(5)[:kind]

# Top-level def variant (non-self).
def first_or_default(arr, default = nil)
  unless arr.empty?
    return arr[0]
  end
  default
end

puts first_or_default(["hi", "bye"])
puts first_or_default([], "fallback")
