# Five behaviours that zr answers exactly as ruby 4.0.7 does. These rows
# catch a change in any of them.
#
#   1. Mixed Integer/Float comparison past 2**53
#   2. A class-level `@x` read through an INHERITED class method
#   3. `UnboundMethod#bind` onto a subclass that overrides the name
#   4. `Struct.new("Name", ...)` namespacing
#   5. A struct constant as a STATIC superclass

# 1. Exact, not through `as f64`.
p 2**53 == (2**53).to_f
p (2**53 + 1) == (2**53 + 1).to_f
p 9007199254740993 > 9007199254740992.0
p [2**53 + 1, 2.0**53].max
p 1.send(:<, 2**53 + 1)

# 2. The receiver's own storage, not the ancestor's.
class Parent
  @x = "parent"
  class << self
    attr_reader :x
  end

  def self.show = @x
end
class Child < Parent
  @x = "child"
end
p Parent.show
p Child.show
p Child.x

# 3. The OWNER's body, not the target's override.
class Base
  def m = "base"
end
class Derived < Base
  def m = "derived"
end
p Base.instance_method(:m).bind(Derived.new).call

# 4. `Struct::Name`, not a bare top-level `Name`.
Named = Struct.new("Named", :a)
p Struct::Named
p Named.name

# 5. A struct constant IS a static superclass, in both spellings.
Point = Struct.new(:x, :y)
class Sum < Point
  def total = x + y
end
p Sum.new(1, 2).total
p Sum.ancestors.include?(Point)

class Doubler < Struct.new(:z)
  def twice = z * 2
end
p Doubler.new(4).twice
