# A class method initializes a local to `nil`, conditionally
# reassigns it through an intermediate variable, and returns the
# local. The method returns the object or nil, not an Integer.
# The local is nil after its first assignment, but a later
# assignment makes it a Foo, and the return type must include both.
#
# Coverage:
#   - the canonical Rails-style `_adapter_find_by_id` shape with
#     an intermediate variable,
#   - the same shape that assigns the local directly inside an
#     `if` (no intermediate),
#   - the simple `nil`-fallback flow control (`return nil unless
#     ...`), where the method returns a Foo or nil.

class Foo
  attr_accessor :tag
  attr_accessor :flag
  def initialize(tag)
    @tag = tag
    @flag = 0
  end
end

class Bar
  def self.find(t)
    result = nil
    if t == "yes"
      instance = Foo.new("found")
      result = instance
    end
    result
  end

  def self.find_direct(t)
    result = nil
    if t == "yes"
      result = Foo.new("direct")
    end
    result
  end

  def self.maybe(t)
    return nil unless t == "yes"
    Foo.new("maybe")
  end
end

x = Bar.find("yes")
puts x.nil? ? "nil" : x.tag       # found

y = Bar.find("no")
puts y.nil? ? "nil" : y.tag       # nil

a = Bar.find_direct("yes")
puts a.nil? ? "nil" : a.tag       # direct

b = Bar.find_direct("no")
puts b.nil? ? "nil" : b.tag       # nil

c = Bar.maybe("yes")
puts c.nil? ? "nil" : c.tag       # maybe

d = Bar.maybe("no")
puts d.nil? ? "nil" : d.tag       # nil
