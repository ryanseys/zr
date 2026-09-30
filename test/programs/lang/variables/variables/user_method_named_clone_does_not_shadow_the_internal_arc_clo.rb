# A Ruby method named `clone` does not change how the program copies
# self or a local internally. So there is no infinite recursion in
# `clone`'s own body. The test uses self-reference, ivar writes (with the
# frozen check), and an Object-typed local re-read.

class Uncopyable
  def initialize
    @n = 1
  end
  def clone
    raise TypeError, "can't clone #{self.class}"
  end
  def bump
    @n += 1
    self
  end
  def n
    @n
  end
end
u = Uncopyable.new
u.bump
puts u.n
begin
  u.clone
rescue TypeError => e
  puts e.message
end
