# A small class whose ivars do not change, as the receiver of a method
# that only calls instance_exec. The method forwards the receiver's own
# ivars as args to the block. The block gets their values.

class Pt
  def initialize(x, y)
    @x = x
    @y = y
  end

  # forwards two ivars to the block
  def combine(&b)
    instance_exec(@x, @y, &b)
  end

  # forwards an ivar and a local
  def scale(k, &b)
    instance_exec(@x, k, &b)
  end
end

p1 = Pt.new(3, 4)
p2 = Pt.new(10, 20)

# expression position: the block value flows into puts
puts(p1.combine { |a, b| a + b })     # 7
puts(p2.combine { |a, b| a * b })     # 200
puts(p1.scale(5) { |x, k| x * k })    # 15

# statement position
p2.combine { |a, b| puts(a + b) }     # 30

puts "done"
