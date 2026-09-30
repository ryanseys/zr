# Polymorphic dispatch where the called method reads `self`. Methods that
# read instance fields and methods that do not touch self both work.

class C
  attr_accessor :n
  def initialize(n)
    @n = n
  end
  def name
    @n.to_s
  end
end

class D
  def name
    "other"
  end
end

def show(o)
  o.name
end

puts show(C.new(42))
puts show(D.new)
