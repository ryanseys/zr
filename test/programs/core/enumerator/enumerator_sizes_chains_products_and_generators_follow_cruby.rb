# Enumerator sizes, chains, products and generators as enumerator.c has them.
a = [1]
e = a.each
m = a.map
a << 2
h = {a: 1}
he = h.each
h[:b] = 2
p e.size, m.size, he.size, h.each_pair.size
p 42.upto(Float::INFINITY).size, 42.downto(-Float::INFINITY).size, 1.upto(-Float::INFINITY).size
o = Object.new
def o.each(*) = yield
p o.to_enum { 1 }.size, o.to_enum { 1 }.each([]).size

chain = [1].to_enum + [2].to_enum
p chain.class, (chain.methods & %i[feed next next_values peek peek_values]), chain.respond_to?(:with_object)
lazy = ((10..).lazy.select(&:even?).take(3) + (21..).lazy.select(&:odd?)).select { |x| x % 3 == 0 }
p lazy.class, lazy.first(3), [1].chain((2..).lazy).class

p Enumerator::Product.new([], 1..).size, Enumerator.product([], 1..).size, Enumerator.product(1..2, 1..).size
p((Enumerator::Product.new(1..3, foo: 1, bar: 2) rescue $!))

p Enumerator.produce(1, size: 10) { |x| x + 1 }.size, Enumerator.produce(size: -> { 5 }) { 1 }.size
p Enumerator.produce(1, size: nil) { 1 }.size, Enumerator.produce { 1 }.size, Enumerator.produce(size: 3) { |x| (x || 0) + 1 }.take(3)
p((Enumerator.produce(a: 1, b: 1) {} rescue $!))

p((Enumerator.new("42") {} rescue $!))
p Enumerator.new(3.9) {}.size, Enumerator.new(Float::INFINITY) {}.size
p(([].to_enum { 0 }.cycle("").size rescue $!))

g = Enumerator::Generator.new(proc { |y| y << 4 << 5; :foo })
p g.each { |x| x }
g.freeze
p((g.__send__(:initialize, proc {}) rescue $!.class))
p((Enumerator::Generator.new(1) rescue $!), (Enumerator::Generator.new rescue $!))
