# A bare `return` (Ruby's "exit early" form) inside an `initialize` body
# stops initialize. `new` still returns the instance, with the ivars set
# so far. The same is true when a subclass reaches it through `super`.

class Box
  attr_reader :data
  def initialize(other = nil)
    @data = "ok"
    return if other.nil?
    @data = other
  end
end

# Default-construct: the bare `return` inside initialize fires;
# `@data` stays at "ok".
b1 = Box.new
puts b1.data           # ok

# Pass an explicit value: the early return is skipped; `@data` is
# overwritten.
b2 = Box.new("hi")
puts b2.data           # hi

# Subclass that reaches the parent's initialize through `super`: the
# parent's bare return ends only the parent's initialize, and the
# subclass then sets @tag.
class TaggedBox < Box
  attr_reader :tag
  def initialize(other = nil, tag:)
    super(other)
    @tag = tag
  end
end

t = TaggedBox.new("payload", tag: "label")
puts t.tag             # label

t2 = TaggedBox.new(tag: "empty")
puts t2.tag            # empty
