p ->(a, b) {}.arity
p ->(a, b = 1) {}.arity
p proc { |a, b = 1| }.arity
p proc { |a, *b| }.arity
p ->(a, b:) {}.arity
p ->(a, **k) {}.arity
p ->() {}.lambda?
p proc {}.lambda?
