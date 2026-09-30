# A bare call to a sibling `def self.X` inside another `def self.Y`
# body in the same module/class is a call to `self.X(...)`, as in
# CRuby. The sibling's params take the types of the call's args.

# 1. Module case: outer cmeth makes a bare call to a sibling
# cmeth that takes a string param.
module Inv
  def self.outer(table)
    inner(table)
    table
  end

  def self.inner(name)
    # `name` must be a String here for this concatenation.
    "rows-for-" + name
  end
end

puts Inv.outer("articles")    # articles
puts Inv.inner("posts")       # rows-for-posts

# 2. Real-class case: sibling cmeth chained through a string
# param.
class Greeter
  def self.outer(x)
    inner(x)
  end

  def self.inner(s)
    "hello, " + s
  end
end

puts Greeter.outer("world")   # hello, world

# 3. Multi-hop chain across three sibling cmeths inside a module,
# so the String type must go through two calls.
module Pipeline
  def self.start(s)
    middle(s)
  end

  def self.middle(t)
    finish(t)
  end

  def self.finish(u)
    "[" + u + "]"
  end
end

puts Pipeline.start("ok")     # [ok]
