# A box that redefines an operator of a core class (Integer#+) gets its
# own operator in its code and in a Binding made in the box, also after a
# collection. Main and another box keep ruby's.
box = Ruby::Box.new
box.eval('class Integer; def +(*) = 42; end')
p box.eval('1 + 2')
p box.eval('1.+(2)')
p box.eval('x = 1; x + 2')
p box.eval('[1, 2].map { |i| i + 1 }')
b = box.eval('binding')
box = nil
p b.eval('1 + 2')
GC.start
p b.eval('1 + 2')
p 1 + 2
x = 1
p x + 2
p [1, 2].map { |i| i + 1 }
p Ruby::Box.new.eval('1 + 2')
p binding.eval('1 + 2')
