# CRuby raises wrong-number-of-arguments / missing-keyword INSIDE the
# callee: the innermost backtrace row is the callee's label at its
# `def` line, and an `initialize`-less `.new` shows the C-frame shape
# `'BasicObject#initialize'` at the CALLER's line. This battery was
# verified verbatim against ruby.

def f(a, b)
  a + b
end
begin
  f(1)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first.split('/').last
end
class Bag
  def initialize(x)
    @x = x
  end
end
begin
  Bag.new(1, 2, 3)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first.split('/').last
end
class Plain; end
begin
  Plain.new(5)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first.split('/').last
end
def kw(x:)
  x
end
begin
  kw
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first.split('/').last
end
