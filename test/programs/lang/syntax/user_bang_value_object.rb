# A user-defined #! on an object with ivars: `!obj` calls the user method
# and answers its value.
class N1
  def initialize(b); @b = b; end
  def !; @b == 0; end
end
p(!N1.new(1))
p(!N1.new(0))
x = N1.new(0)
p(!x)
p(!!x)

class N2
  def initialize(b); @b = b; end
  def !=(o); @b != o; end
end
p(N2.new(3) != 3)
p(N2.new(3) != 4)
