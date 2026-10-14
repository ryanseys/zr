# Enumerator::Yielder#to_proc is method(:yield).to_proc, as CRuby's
# yielder_to_proc makes it: a lambda that yields its arguments.
e = Enumerator.new do |y|
  pr = y.to_proc
  p pr.lambda?, pr.arity
  pr.call(1)
  pr.call(2, 3)
  pr.call
  [4, 5].each(&pr)
  [[6, 7]].each(&pr)
  { a: 1 }.each(&pr)
  pr.call(8, k: 9)
end
e.each { |*args, **kw| p [args, kw] }
p Enumerator.new { |y| [1, [2, 3]].each(&y) }.to_a
