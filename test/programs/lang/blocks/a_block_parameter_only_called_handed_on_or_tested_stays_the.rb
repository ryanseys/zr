# A `&b` parameter that the method only calls, hands on or tests
# stays the block it was given; every shape reads as before.
def call_it(x, &b) = b.call(x)
def hand_on(&b) = [1, 2].map(&b)
def test_it(&b) = b ? :some : :none
def and_it(&b) = b && b.call(1)
def safe_it(&b) = b&.call(3)
def nested(&b) = [1, 2].map { |x| b.call(x) }
def nested_hand(&b) = [[1], [2]].map { |xs| xs.map(&b) }
def with_keywords(&b) = b.call(1, k: 2)
def with_splat(*xs, &b) = b.call(*xs)
def to_super(&b) = call_it(5, &b)
class Base; def go(&b) = b.call(:base); end
class Kid < Base; def go(&b) = super; end
class Kid2 < Base; def go(&b) = super(&b); end
p call_it(2) { |x| x * 10 }
p hand_on { |x| x + 1 }
p test_it { }
p test_it
p and_it { |x| x + 1 }
p and_it
p safe_it { |x| x + 1 }
p safe_it
p nested { |x| x * 3 }
p nested_hand { |x| -x }
p with_keywords { |x, k:| [x, k] }
p with_splat(1, 2) { |a, b| a - b }
p to_super { |x| x + 100 }
p Kid.new.go { |x| x }
p Kid2.new.go { |x| x }
# A lambda keeps its arity and its own return.
l = ->(x) { x * 2 }
p call_it(4, &l)
begin
  call_it(4) { |x| x }.then { with_splat(1, 2, &l) }
rescue ArgumentError => e
  puts e.message
end
# `break` and `return` from the block go where they always went.
def breaker(&b) = [b.call(1), :after]
p(breaker { |x| break x })
def returner
  call_it(1) { |x| return :early }
  :late
end
p returner
# No block: the call raises as a send to nil does.
begin
  call_it(1)
rescue NoMethodError => e
  puts e.message
end
# A block kept by an inner block that runs after the method returned.
def keeper(&b)
  proc { b.call(7) }
end
kept = keeper { |x| x + 1 }
GC.start
p kept.call
def keeper2(&b)
  define_singleton_method(:later) { b.call(8) }
  nil
end
keeper2 { |x| x * 2 }
GC.start
p later
# A method that escapes the block still has a Proc.
def escaper(&b) = b
pr = escaper { |x| x }
p pr.class
p pr.call(9)
# A call in a loop makes no object a turn.
def turns(n, &b)
  i = 0
  while i < n
    b.call(i)
    i += 1
  end
end
turns(10) { |x| x }
before = GC.stat(:total_allocated_objects)
turns(10_000) { |x| x }
made = GC.stat(:total_allocated_objects) - before
p made < 10
# A Proc subclass with its own `call` is asked, not run as a block.
class Sub < Proc
  def call(*) = :sub
end
p call_it(1, &Sub.new { |x| x })
# Redefining Proc#call reaches every call of a block parameter.
class Proc
  alias zr_test_call call
  def call(*args) = [:redefined, *args]
end
p call_it(6) { |x| x }
class Proc
  alias call zr_test_call
end
p call_it(6) { |x| x }
# define_method bodies and blocks with a block parameter of their own.
define_method(:dm) { |x, &b| b.call(x) }
p dm(3) { |x| x + 1 }
pb = proc { |&b| b ? b.call : :none }
p pb.call { :given }
p pb.call
