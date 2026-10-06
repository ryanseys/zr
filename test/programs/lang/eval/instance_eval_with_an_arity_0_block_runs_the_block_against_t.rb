# An arity-0 DSL trampoline: `def m(&b); instance_eval(&b); end`.
#
# instance_eval runs the block with `self` set to the receiver, so
# receiverless calls in the block go to the receiver's class.

# 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
#    the Builder instance, so `add(10)` resolves as Builder#add.
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

  def configure(&block)
    instance_eval(&block)
  end
end

# An arity-0 DSL trampoline: `def m(&b); instance_eval(&b); end`.
#
# instance_eval runs the block with `self` set to the receiver, so
# receiverless calls in the block go to the receiver's class.

# 1. Basic trampoline: `recv.configure { add 10 }` rebinds self to
#    the Builder instance, so `add(10)` resolves as Builder#add.
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

  def configure(&block)
    instance_eval(&block)
  end
end

b = Builder.new
b.configure do
  add(10)
  add(20)
  add(12)
end
puts b.total              #=> 42

