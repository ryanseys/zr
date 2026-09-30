# An instance_exec result used through an intermediate local inside a method
# (not a bare trampoline body), in value position. The method forwards its
# block to a receiverless instance_exec, binds the result to a local, and
# transforms it. The method returns the transformed value of the block.

# Receiver with a method that changes its state.
class Calc
  def initialize
    @base = 10
    @hits = 0
  end
  def bump
    @hits = @hits + 1
  end
  def run(x, &b)
    r = instance_exec(x, @base, &b)
    r * 2
  end
end

c = Calc.new
c.bump
puts(c.run(5) { |a, b| a + b })       # (5 + 10) * 2 = 30
puts(c.run(100) { |a, b| a - b })     # (100 - 10) * 2 = 180

# Receiver of a small class with no method that changes its state.
class Point
  def initialize(x, y)
    @x = x
    @y = y
  end
  def fold(&b)
    acc = instance_exec(@x, @y, &b)
    acc + 1
  end
end

p1 = Point.new(3, 4)
p2 = Point.new(10, 20)
puts(p1.fold { |a, b| a + b })        # (3 + 4) + 1 = 8
puts(p2.fold { |a, b| a * b })        # (10 * 20) + 1 = 201

puts "done"
