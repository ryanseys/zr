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

puts "done"
