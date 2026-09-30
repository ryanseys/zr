# An ivar that can be nil or a String, because a `kwarg: nil`
# default makes the writer's param nullable. The ivar is then
# stored as a value in a Hash of String keys and String values.
#
# action_controller/base.rb has this pattern:
# `@location = location` (location is a `location: nil` kwarg)
# followed by `res.headers["Location"] = controller.location`
# at the Tep::Server entry. Same pattern, minimized here.

class C
  attr_reader :loc

  def initialize
    @loc = nil
  end

  def render(loc: nil)
    @loc = loc
  end
end

class Bag
  attr_reader :h

  def initialize
    @h = {}
    @h["k"] = "v"
  end
end

c = C.new
c.render(loc: "/b")
b = Bag.new
b.h["k2"] = c.loc
puts b.h["k"]
puts b.h["k2"]
