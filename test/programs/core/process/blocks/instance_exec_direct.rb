# Direct instance_exec: `recv.instance_exec(args) { |params| body }` with no
# wrapper method. This is what most Ruby code writes. The block runs with
# self set to the receiver, and the call-site args bind to the block params.

# 1. Bare direct call with one arg. The block body adds the call-site
#    arg to the receiver's @sum via the method `add`. Bare method
#    calls inside the block resolve against the receiver's class.
class Builder
  def initialize
    @sum = 0
  end

  def add(n)
    @sum = @sum + n
  end

  def total
    @sum
  end
end

b = Builder.new
b.instance_exec(10) { |n| add(n) }
b.instance_exec(20) { |n| add(n) }
b.instance_exec(12) { |n| add(n) }
puts b.total                  #=> 42

# 2. Two args at the call site forward into two block params. Block
#    body computes with them and changes the receiver's ivar through
#    the new self.
class Acc < Builder
end

a1 = Acc.new
a2 = Acc.new
a1.instance_exec(3, 4) { |s, k| add(s * k) }
a2.instance_exec(7, 2) { |s, k| add(s * k) }
a1.instance_exec(1, 0) { |s, k| add(s + k) }
puts a1.total                 #=> 13
puts a2.total                 #=> 14

# 3. Zero-arg form (equivalent to instance_eval).
b2 = Builder.new
b2.instance_exec { add(100) }
b2.instance_exec { add(50) }
puts b2.total                 #=> 150

puts "done"
