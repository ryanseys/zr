# `k.new` where k is a Class value switches over the classes that could be
# there. A MODULE has no `new`, so the switch leaves modules out.
module Counted
  def initialize
    @n = 7
  end
  def n = @n
end
class Plain
  def n = 0
end
class Counted1
  include Counted
end
p [Plain, Counted1].map { |k| k.new.n }
p [Counted1].map { |k| k.new.n }
KL = [Plain, Counted1]
KL.each { |k| p k.new.n }
p({ a: Counted1 }.map { |_, k| k.new.n })
p Counted1.new.n
k = Counted1
p k.new.n

module Sized
  def initialize(n)
    @n = n
  end
  def n = @n
end
class Box
  include Sized
end
p [Box].map { |c| c.new(3).n }
