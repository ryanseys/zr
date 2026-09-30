# Ruby names that collide with the compiler's own vocabulary must not leak
# into the generated program: a class named after a builtin type, a method
# named after a keyword, and Ruby's `_` local, which the generated program
# has no named binding for. All are mangled on the way out, and none of the
# mangling is observable from Ruby.

# --- Classes named after builtin types ------------------------------------

class Vec
  def initialize(x, y)
    @x = x
    @y = y
  end
  attr_reader :x, :y

  def +(other)
    Vec.new(@x + other.x, @y + other.y)
  end

  def to_s = "Vec(#{@x}, #{@y})"
end

v = Vec.new(1, 2) + Vec.new(10, 20)
puts v
p v.x
p v.class
p v.class.name
p v.is_a?(Vec)

class Option
  def initialize(value) = @value = value
  def some? = !@value.nil?
  def value_or(default) = @value.nil? ? default : @value
end
p Option.new(5).some?
p Option.new(nil).some?
p Option.new(nil).value_or(:fallback)
p Option.new(:got).value_or(:fallback)

class Box
  def initialize(v) = @v = v
  def get = @v
end
p Box.new("boxed").get

class Result
  def initialize(ok) = @ok = ok
  def ok? = @ok
end
p Result.new(true).ok?

# Inheritance between prelude-named classes.
class Iterator
  def each = [1, 2].each { |i| yield i }
end
class Send < Iterator; end
out = []
Send.new.each { |i| out << i }
p out
p Send.new.is_a?(Iterator)

# A prelude-named class used as a Hash key and in a collection.
registry = { Vec => :vector, Option => :option }
p registry[Vec]
p [Vec.new(0, 0), Vec.new(1, 1)].map(&:to_s)

