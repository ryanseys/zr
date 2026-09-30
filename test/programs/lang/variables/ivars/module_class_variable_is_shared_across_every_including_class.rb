# Verified against real Ruby first: `@@total` declared inside the
# MODULE's own body is genuinely owned by the module itself -- every
# class that includes it (even two entirely unrelated classes) shares
# the SAME storage, not one copy per includer. The owner is the module a
# materialized method's body actually came from, not whichever class it is
# materialized onto.

module Shared
  @@total = 0
  def add(n)
    @@total += n
  end
  def total
    @@total
  end
end
class Left
  include Shared
end
class Right
  include Shared
end
l = Left.new
r = Right.new
l.add(5)
r.add(7)
puts l.total
puts r.total
