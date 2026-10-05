# Complex: text forms, fdiv, <=> through coerce, to_r, Complex() with
# exception: false, and Marshal data with @real/@image ivars.
p %w[--8i 1+-2i -i +i .33 -.33i 1.e3 .5e2 1/.2 .3/4 1_.5 3i 1+2i i 1-i 2@1].map { |s| [s, (Complex(s) rescue $!.class), s.to_c] }

p Complex(1, 2).fdiv(Complex(3, 4))
p Complex(1, 2).fdiv(2)
p Complex(1e308, 1e308).fdiv(Complex(1e308, 1e308))

class Meter
  def initialize(n) = @n = n
  def coerce(other) = [other, Complex(@n)]
end
p Complex(3) <=> Meter.new(2)
p Complex(3) <=> 3.0
p Complex(3, 1) <=> 3
p Complex(3) <=> Complex(3, 1)
p Complex(3) <=> "3"

p Complex(1, 0).to_r
p Complex(1, 0.0).to_r
p Complex(1, Rational(0)).to_r
p((Complex(1, 2).to_r rescue $!.message))

class Broken
  def to_c = raise(ArgumentError, "no")
end
p Complex(Broken.new, exception: false)
p((Complex(Broken.new) rescue $!.message))

p Marshal.load("\x04\x08o:\x0cComplex\x07:\x0a@reali\x06:\x0b@imagei\x07")
p Marshal.load("\x04\x08o:\rRational\x07:\x11@denominatori\x07:\x0f@numeratori\x06")
p Marshal.load(Marshal.dump(Complex(1, 2))), Marshal.load(Marshal.dump(Rational(1, 3)))
p Marshal.load("\x04\x08o:\x0cComplex\x07:\x0a@reali\x06:\x0b@imagei\x07", freeze: true).frozen?
