# Kernel#Rational and Rational.convert read their parts as nurat_convert
# does, and arithmetic keeps the class of the receiver.
class RationalSub < Rational; end
c = (RationalSub.__send__(:convert, 1) rescue $!)
p c, c.class
p((c + 1).class, (c - 1).class) rescue p $!
p (Rational(Complex(1,2),2) rescue $!)
p (Rational(2,Complex(1,2)) rescue $!)
x = 2 ** Rational(2)
p x, x.class
p 2 ** Rational(-2), 0 ** Rational(0), (2 ** Rational(1, 2))
p((Marshal.load("\x04\bU:\rRational[\ai\x060") rescue $!))
p((Marshal.load("\x04\bU:\rRational[\ai\x06i\x05") rescue $!))
p((Marshal.load("\x04\x08o:\x0dRational\x07:\x11@denominatori\x07:\x0f@numerator0") rescue $!))
p((Marshal.load("\x04\x08o:\x0dRational\x07:\x11@denominatori\x07:\x0f@numeratori\x06") rescue $!))
p Rational("5/3x", exception: false)
p Rational("1/0", exception: false)
p Rational(1, 0, exception: false) rescue p $!
p Rational(nil, exception: false), Rational(Object.new, exception: false)
p Rational(1, nil, exception: false)
c = RationalSub.__send__(:convert, 1)
c2 = c - 1
p((c - c2).class, (c * 2).class, (c / 3).class, (-c).class, c.abs.class, (c ** 2).class, (c ** 0).class)
c5 = Marshal.load(Marshal.dump(c))
p c5, c5.class, c.hash == Rational(1).hash, [c.eql?(Rational(1)), Rational(1).eql?(c)]
p (RationalSub.__send__(:convert, 1, 2, 3) rescue $!)
p Rational(Complex(1, 0), 2), Rational(1.5, 2), Rational("3/4", "1/2"), Rational(3, 0.5)
p (Rational(Object.new, 1) rescue $!), (Rational(1, Object.new) rescue $!), (Rational(Object.new) rescue $!)
p Rational(Object.new, 1, exception: false), Rational(1, Object.new, exception: false)
o = Object.new; def o.to_int = 3
p (Rational(o) rescue $!), (Rational(o, 2) rescue $!)
p (Rational(3, 2) ** (2**64) rescue $!), Rational(-1) ** 3, Rational(-1) ** 4, (Rational(0) ** -1 rescue $!)
p Rational(1, 2) ** 0.0, Rational(1, 2) ** Rational(0), 2 ** Rational(1, 2)
p (Rational(1,2).coerce(Complex(3, 0))), Rational(1, 3).rationalize(Rational(1, 100))
