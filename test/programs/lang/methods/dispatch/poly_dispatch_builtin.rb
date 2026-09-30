# Polymorphic dispatch over a parameter that gets more than one class
# picks the right `[]` from the run-time class — a user class's
# `def [](x)` for Foo.new, Array#[] for an Array literal.

class Foo
  def [](x)
    42
  end
end

def read0(a)
  a[0]
end

puts read0(Foo.new)
puts read0([100, 200, 300])
