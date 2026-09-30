# A yielding method reached through a poly receiver.
#
# The call runs the method of the receiver's own class, with the block. It
# does not raise NoMethodError for a class that defines the method, so the
# whole block API of each class works.
#
# A yield nested inside a block works, and two call sites can pass blocks
# that give back values of different types.

class A
  def go
    yield 5
  end

  def guarded
    block_given? ? yield(1) : 99
  end

  def early
    yield 1
    return 42
  end

  def withargs(a, b)
    yield a + b
  end

  def twice
    yield(1) + yield(2)
  end
end

class B
  def go
    0
  end

  def guarded
    -1
  end

  def early
    -3
  end

  def withargs(a, b)
    a - b
  end

  def twice
    -4
  end
end

def pick(n)
  n == 1 ? A.new : B.new
end

p pick(1).early { |v| v }
p pick(2).early { |v| v }

