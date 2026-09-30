# `obj.class` on an instance gives the class FROM the instance,
# and class methods called on that class run.
#
# Coverage: chained .class.<cmeth>, plain `obj.class.to_s`, and the
# string-interpolation form `"#{self.class}"` that optcarrot's
# default inspect uses.

class Foo
  def self.greet
    "hello-from-foo"
  end
end

f = Foo.new
puts f.class.greet              # hello-from-foo
puts f.class.to_s               # Foo

class Bar
  attr_accessor :v
  def initialize
    @v = 0
  end
  def describe
    "#<#{ self.class }>"
  end
end

b = Bar.new
puts b.describe                 # #<Bar>

# Subclass: dispatch should pick up the cmeth defined on the
# inherited class. The lookup walks the parents, as in CRuby.
class Base
  def self.kind
    "base-kind"
  end
end

class Child < Base
end

c = Child.new
puts c.class.kind               # base-kind
