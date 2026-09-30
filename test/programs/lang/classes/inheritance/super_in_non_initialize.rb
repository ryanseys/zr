# `super` in a non-`initialize` instance method calls the parent's
# method of the same name, found up the parent chain. The result
# has the type that the parent's method returns.

class A
  def value
    10
  end

  def doubled(x)
    x * 2
  end
end

class B < A
  def value
    super         # bare super forwards no args
  end

  def doubled(x)
    super(x) + 1  # explicit super(arg) -> A.doubled(x) + 1
  end
end

class C < B
  def value
    super + 5     # B.value calls A.value (10) -> 10 + 5 = 15
  end
end

b = B.new
puts b.value.to_s       # 10
puts b.doubled(3).to_s  # 6 + 1 = 7

c = C.new
puts c.value.to_s       # 15
