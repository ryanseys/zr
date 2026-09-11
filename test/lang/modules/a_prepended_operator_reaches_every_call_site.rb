# Each redefinition falls back to `super`, so everything else the
# operator does stays as it was.
def add(a, b) = a + b
def sub(a, b) = a - b
def mul(a, b) = a * b
def at(a, i) = a[i]

p add(1, 2), sub(5, 1), mul(2, 3), at([7], 0)

module Plus
  def +(o) = o == 100 ? :plus : super
end
Integer.prepend(Plus)
p 1 + 100, add(1, 100), add(1, 2)

module Later; end
Integer.prepend(Later)
module Later
  def -(o) = o == 100 ? :later : super
end
p 5 - 100, sub(5, 100), sub(5, 1)

class Integer
  alias_method :times_before, :*
  def *(o) = o == 100 ? :redefined : times_before(o)
end
p 2 * 100, mul(2, 100), mul(2, 3)

module Index
  def [](i, *rest) = i == 100 ? :index : super
end
Array.prepend(Index)
p [7][100], at([7], 100), at([7], 0)

class Integer
  private :%
end
def mod(a, b) = a % b
begin
  p mod(7, 2)
rescue NoMethodError => e
  p e.message
end

__END__
3
4
6
7
:plus
:plus
3
:later
:later
4
:redefined
:redefined
6
:index
:index
7
"private method '%' called for an instance of Integer"
