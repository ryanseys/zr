# A comparison treats a coerce that gives no pair as no coerce, while
# arithmetic raises. Complex with exception: false gives nil for an
# imaginary part that is no real number.
o = Object.new
def o.coerce(_) = nil
p((1 < o rescue $!), (2**70 < o rescue $!), (1 + o rescue $!), (1 <=> o), (2**70 <=> o))
p Complex("a", :sym, exception: false), Complex(:sym, :sym, exception: false), Complex(0, :sym, exception: false)
p((Complex(:sym, 1, exception: false) rescue $!))
q = Object.new
def q.coerce(_) = :nope
p((1 <=> q rescue $!), (2**70 < q rescue $!))
