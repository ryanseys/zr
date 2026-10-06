# Each Rational operator takes an operand that is no Numeric through its
# coerce, remainder too.
class ObjectX
  def +(x) = Rational(1)
  %i[- * / quo div % remainder **].each { |m| alias_method m, :+ }
  def coerce(x) = [x, Rational(1)]
end
x = ObjectX.new
%w(+ - * / quo div % remainder **).each { |op| p [op, Rational(1).__send__(op, x)] }
o = Object.new
def o.coerce(x) = [x, Rational(1)]
p [Rational(1).remainder(o), 1.remainder(o), 1.0.remainder(o)]
