# Polymorphic `[]` and `length` dispatch must reach an array of user
# objects. Such an array must not be read as an Integer array.
#
# `lenof([Foo.new(1), Foo.new(2)])` prints 2.

class Foo
  def initialize(n)
    @n = n
  end
  attr_reader :n
end

class Bar
  def length
    99
  end

  def [](_)
    77
  end
end

def lenof(a)
  a.length
end

def first(a)
  a[0]
end

# `length` over mixed call sites — IntArray, PtrArray<Foo>, and a
# user class. The PtrArray branch is the new one for this PR.
puts lenof([1, 2, 3])                  # 3
puts lenof([Foo.new(1), Foo.new(2)])   # 2
puts lenof(Bar.new)                    # 99

# `[]` over the same shapes.
puts first([10, 20, 30])               # 10
foo = first([Foo.new(42)])
puts foo.n                             # 42
puts first(Bar.new)                    # 77
