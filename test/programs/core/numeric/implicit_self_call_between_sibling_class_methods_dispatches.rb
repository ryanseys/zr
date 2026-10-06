# Found while testing `class << self`: a no-receiver call from one class
# method to a SIBLING class method (`def self.a; b; end` calling
# `def self.b`) must dispatch correctly, same as `ClassName.foo(...)`.

class Widget
  def self.create
    helper
  end
  def self.helper
    "made"
  end
end
puts Widget.create

class MathUtils
  class << self
    def sum_of_squares(a, b)
      square(a) + square(b)
    end
    def square(x)
      x * x
    end
  end
end
puts MathUtils.sum_of_squares(3, 4)
