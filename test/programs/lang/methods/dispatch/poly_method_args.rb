# Polymorphic method dispatch must pass arguments through to the
# selected class's method. The method gets every call-site argument.

class Doubler
  def call(x)
    x * 2
  end
end

class Tripler
  def call(x)
    x * 3
  end
end

def apply(a, x)
  a.call(x)
end

puts apply(Doubler.new, 5)
puts apply(Tripler.new, 5)
