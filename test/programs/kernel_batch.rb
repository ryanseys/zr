# A Kernel-corpus batch (native only: exec, caller, require).
class Pair
  def initialize(a, b) = (@a, @b = a, b)
  def to_ary = [@a, @b]
end
def one(v) = yield(v)
p(one(Pair.new(1, 2)) { |a, b| [a, b] })
p(one(Pair.new(1, 2)) { |a| a.class })
p(one(Pair.new(1, 2)) { |*a| a.size })
class Bad
  def to_ary = 3
end
begin; one(Bad.new) { |a, b| p [a, b] }; rescue TypeError => e; p e.message; end
class N
  def to_ary = nil
end
one(N.new) { |a, b| p [a.class, b] }
class BadProc
  def to_proc = :not_a_proc
end
begin; [1].map(&BadProc.new); rescue TypeError => e; p e.message; end
p(42.__id__ == 42.object_id, nil.__id__, :sym.__id__ == :sym.object_id, :sym.object_id.class, 1.0.object_id, 2.5.object_id, (-1.0).object_id == (-1.0).__id__)
class LiarInt
  def to_int = "nope"
end
class Two
  def to_int = 2
end
def err
  yield
rescue TypeError => e
  puts "#{e.class}: #{e.message}"
end
err { [1, 2, 3][LiarInt.new] }
err { [1, 2].first(LiarInt.new) }
err { "ab" * LiarInt.new }
p [1, 2] * Two.new, "ab" * Two.new, [10, 20, 30][Two.new], [10, 20, 30].first(Two.new), [1, 2, 3][2.7], [1, 2] * 2.9
def takes_block = block_given? ? yield : :no_block
puts method(:takes_block).call { :ran }
pr = method(:takes_block).to_proc
puts pr.call { :ran }
puts pr.call(&-> { :ran })
def relay(&blk) = blk.call { :ran }
puts relay(&method(:takes_block))
puts method(:takes_block).to_proc.curry.call { :ran }
puts(proc { |&b| takes_block(&b) }.call { :ran })
def try(label)
  p [label, yield]
rescue ArgumentError => e
  p [label, :raised, e.message]
end
pr2 = proc { |a| a }
def wrapper(&b) = lambda(&b)
try(:bare)          { lambda { 1 }.lambda? }
try(:send_sym)      { Kernel.send(:lambda) { 1 }.lambda? }
try(:forwarded)     { lambda(&pr2).lambda? }
try(:wrapper)       { wrapper { 1 }.lambda? }
try(:method_object) { Kernel.method(:lambda).call { 1 }.lambda? }
try(:public_send)   { Kernel.public_send(:lambda) { 1 }.lambda? }
def helper
  c = caller
  p c.class, caller(1, 0), caller(0, 1).size, caller(50)
end
helper
def it_p = iterator?
p it_p, it_p { }
require "set"
p $LOADED_FEATURES.any? { |f| f.include?("set") }, $LOADED_FEATURES.empty?
class Pat
  def to_regexp = /ab+/i
end
p Regexp.try_convert(Pat.new), Regexp.try_convert(/lit/), Regexp.try_convert("ab+"), Regexp.try_convert(nil)
class Runner
  def exec(*args) = [:mine, *args]
end
r = Runner.new
p r.private_methods.include?(:exec), r.public_methods.include?(:exec), r.exec(1)
class Bare; end
p Bare.new.private_methods.include?(:exec), Bare.new.public_methods.include?(:exec)
begin; exec("/no/such/cmd"); rescue SystemCallError => e; p e.class, e.message; end
class S < String; end
class A < Array; end
class H < Hash; end
s = S.new("x"); a = A.new([1]); h = H.new(5)
puts s.to_s.class, s.to_str.class, a.to_a.class, h.to_h.class, h.to_h.default, a.to_ary.class, h.to_hash.class
puts a.dup.push(2).class, s.dup.concat("y").class, s.upcase.class, a.map { |v| v }.class
p s.to_s.equal?(s), "x".to_s.frozen?, a.to_a.equal?(a), [1].to_a.equal?([1]), h.to_h.equal?(h)
x = "plain"; p x.to_s.equal?(x); y = [1]; p y.to_a.equal?(y); z = {}; p z.to_h.equal?(z)
class Backwards < String
  def <=>(o); o.to_s <=> to_s; end
end
p [Backwards.new("aaa"), Backwards.new("bbb")].sort.map(&:to_s)
class A2 < Array
  def initialize_copy(o)
    super
    @c = 1
  end
end
p A2.new([1]).dup.instance_variable_get(:@c), A2.new([1]).dup.class
str = "q"
str.instance_variable_set(:@q, 1)
p str.dup.instance_variable_get(:@q), str.dup.frozen?, "y".freeze.dup.frozen?, "y".freeze.clone.frozen?
