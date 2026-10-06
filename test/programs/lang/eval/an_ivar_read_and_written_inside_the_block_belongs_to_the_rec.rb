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

# 2. Multiple statements inside the block — each receiverless call
#    dispatches against the rebound class, including reads.
class Counter
  def initialize
    @n = 0
  end

  def bump
    @n = @n + 1
  end

  def get
    @n
  end

  def with(&block)
    instance_eval(&block)
  end
end

c = Counter.new
c.with do
  bump
  bump
  bump
end

# 3. Nested trampolines compose: an outer Builder#configure block
#    contains an inner Counter#with block. The outer self comes back
#    after the inner block returns.
b2 = Builder.new
c2 = Counter.new
b2.configure do
  add(7)
  c2.with do
    bump
    bump
  end
  add(35)
end

# 4. Ivar read/write inside the block body. `self` is the receiver,
#    so `@n = ...` writes the ivar of the receiver, not of the
#    outer self.
c3 = Counter.new
c3.with do
  @n = @n + 5
  @n = @n + 3
end
puts c3.get               #=> 8

