# instance_exec forwards positional args from the call site into the
# block's parameters. In other ways it is like instance_eval:
#
#   def configure(x, &block)
#     instance_exec(x, &block)   # x flows into block param at call site
#   end
#   b.configure(10) { |n| add(n) }   # n == 10 inside the block
#
# Inside the block, self is the receiver. The block can also read and
# write the locals of the scope around the call.

# 1. Single fixed arg, statement form: forwards the call-site arg
#    into the block param, then bare method calls go to the
#    receiver's class, as with instance_eval.
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

  def configure(x, &block)
    instance_exec(x, &block)
  end
end

# 2. Two fixed args, ivar read/write inside the block: the block uses
#    both args and the @ivars of the receiver. Acc is a subclass of
#    Builder, and the test makes two instances of it.
class Acc < Builder
  def bump_by(step, k, &block)
    instance_exec(step, k, &block)
  end
end

a1 = Acc.new
a2 = Acc.new                  # a second instance
a1.bump_by(3, 4) { |s, k| add(s * k) }
a2.bump_by(7, 2) { |s, k| add(s * k) }
a1.bump_by(1, 0) { |s, k| add(s + k) }
puts a1.total                 #=> 13
puts a2.total                 #=> 14

