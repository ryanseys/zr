# Locals inside `initialize` work as in any other method.

class T_init_locals_Test
  attr_reader :a
  def initialize
    x = 1
    @a = x
  end
end

class T_init_locals_Sum
  attr_reader :total
  def initialize(n)
    s = 0
    i = 0
    while i < n
      s = s + i
      i = i + 1
    end
    @total = s
  end
end

class T_init_locals_Compound
  attr_reader :result
  def initialize(x, y)
    a = x * 2
    b = y + 1
    @result = a + b
  end
end

t = T_init_locals_Test.new
puts t.a              # 1

s = T_init_locals_Sum.new(5)
puts s.total          # 10

c = T_init_locals_Compound.new(3, 4)
puts c.result         # 11
