# `enum.to_set` desugars to `Set.new(enum.to_a)`, but a class that defines its
# OWN to_set keeps it. Here a user to_set returns a Hash of pending writes,
# and the call answers that Hash, not a Set.
require "set"

class Jar
  def initialize
    @out = {}
  end
  def []=(k, v)
    @out[k] = v
    v
  end
  def to_set          # NOT Enumerable#to_set
    @out
  end
end

jar = Jar.new
jar["a"] = "1"
jar["b"] = "2"
h = jar.to_set
p h.keys
p h["b"]
p h.class.to_s

# ... while a real Enumerable receiver in the SAME program still desugars
s = [3, 1, 3, 2].to_set
p s.class.to_s
p s.size
p s.include?(3)
p (1..4).to_set.size
