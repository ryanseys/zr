# A block with no parameters takes any arguments, keywords too, and they
# leave no trace for the first call in its body: Integer and Rational,
# and the `1r` and `2i` literals, take keywords of their own. A lambda
# with no parameters counts the keywords as one argument.
p proc { Integer("1") }.call(foo: 1)
p proc { 1r }.call(1, 2i, foo: :three) {}
p proc { [2i, Rational(1, 2)] }.call(foo: 1, bar: 2)
p proc { Integer("x", exception: false) }.call(**{ a: 1 })
p proc { Float("1.5") }.call({ foo: 1 }, bar: 2)

def yields = yield(1, foo: 2)
p yields { Integer("3") }
def passes(&b) = b.call(k: 1)
p passes { Rational(3, 4) }
p((proc { Integer("4") } === { x: 1 }))

begin
  lambda { Integer("5") }.call(foo: 1)
rescue ArgumentError => e
  p e.message
end
p lambda { Integer("6") }.call(**{})

class Maker
  define_method(:none) { Integer("7") }
end
begin
  Maker.new.none(foo: 1)
rescue ArgumentError => e
  p e.message
end
p Maker.new.none

p eval("proc { 1r }").call(1, foo: 2)
p eval("proc { Integer('8') }").call(**{ z: 1 })
