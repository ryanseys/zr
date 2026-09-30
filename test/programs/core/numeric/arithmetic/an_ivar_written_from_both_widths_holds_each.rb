# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

# The same is true for an ivar or class variable: it can hold a Bignum at one
# time and a small Integer, such as `@n = 0`, at another.
class Acc
  attr_reader :n

  def initialize(seed = 0)
    @n = seed
  end

  def add(v)
    @n = @n + v
    @n
  end

  def bump
    @n += 1     # op-assign on a Bignum value
    @n
  end

  def reset
    @n = 0
  end
end

a = Acc.new
p a.add(1)
p a.add(2**80)
p a.bump
p a.n
p a.reset
p a.add(2**64)
p Acc.new(5).add(2**70)

