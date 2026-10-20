# A def that the tree walk runs is a define_method of the walk; its
# Method still gives the parameters, the arity and the inspect of the def.
eval(<<~RUBY)
  def ev(a, &nil) = a
  def two(a, b = 1, *r, k:, **o, &blk) = [a, b, r, k, o, blk]
  def kw(a, k: 1) = [a, k]
  def anon(*, **, &) = 1
  def fwd(...) = 1
RUBY
%i[ev two kw anon fwd].each do |name|
  m = method(name)
  p [name, m.parameters, m.arity, m.inspect[/\([^)]*\)/]]
end
p ev(1), kw(2), two(1, k: 3)
