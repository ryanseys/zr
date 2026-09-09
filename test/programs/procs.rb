p proc { }.arity, proc { |a| }.arity, proc { |a, b| }.arity, proc { |a, b = 1| }.arity, proc { |*a| }.arity, proc { |a, *b| }.arity, proc { |a, k:| }.arity, proc { |(a, b)| }.arity
p lambda { }.arity, lambda { |a| }.arity, lambda { |a, b = 1| }.arity, lambda { |*a| }.arity, lambda { |a, k:| }.arity, lambda { |a, k: 1| }.arity, ->(a, b) {}.arity, ->(**kw) {}.arity
p proc { |a, b = 1, *r, c, k:, o: 2, **kw, &blk| }.parameters
p lambda { |a, b = 1, *r, c, k:, o: 2, **kw, &blk| }.parameters
p proc { |(a, b), c| }.parameters, proc { |x| }.parameters, proc { }.parameters, ->(x) {}.parameters
p :upcase.to_proc.arity, :upcase.to_proc.parameters, :upcase.to_proc.lambda?
p proc { |x| }.lambda?, lambda { |x| }.lambda?, proc { |a, | }.arity, proc { |a, | }.parameters
def m(x, y = 1) = nil
p method(:m).to_proc.arity, method(:m).to_proc.parameters

add = ->(a, b) { a + b }
p add.call(1, 2), add.(3, 4), add[5, 6], add.arity
begin
  add.call(1)
rescue ArgumentError => e
  p e
end
counter = 0
inc = proc { counter += 1 }
3.times(&inc)
p counter
p proc { |a, b| [a, b] }.call(1), proc { |a, b| [a, b] }.call(1, 2, 3), proc { |a, b| [a, b] }.call([4, 5])
p lambda { |a, b| [a, b] }.call(1, 2)
sq = proc { |x| x * x }
p [1, 2, 3].map(&sq)

