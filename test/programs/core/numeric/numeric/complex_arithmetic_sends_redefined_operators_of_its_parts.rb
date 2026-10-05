# Complex's arithmetic sends its parts' operators by name, as CRuby's
# f_add and f_mul do, so a redefined Integer, Float or Rational operator
# applies.
class Integer
  alias_method :plus, :+
  remove_method :+
  def +(other) = 42
end
p Complex(1, 2) + Complex(0, 1)
p Complex(1, 2) + 1

class Integer
  remove_method :+
  alias_method :+, :plus
end
p Complex(1, 2) + Complex(0, 1)

class Float
  alias_method :times, :*
  remove_method :*
  def *(other) = 42.0
end
p Complex(2.0, 0.0) * Complex(1, 2)

class Rational
  remove_method :-
  def -(other) = 355/113r
end
p Complex(1r, 2r) - Complex(0r, 1r)
