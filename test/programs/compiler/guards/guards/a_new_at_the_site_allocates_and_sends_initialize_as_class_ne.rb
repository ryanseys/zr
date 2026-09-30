# `new` at the site: every count of arguments, keywords, a splat, a
# private initialize, a class's own new, an initialize redefined after
# the site ran, a raise inside it, and a class with no allocator.
class P0; def initialize = (@a = :none); attr_reader :a; end
class P2; def initialize(x, y) = (@a = [x, y]); attr_reader :a; end
class P5; def initialize(a, b, c, d, e) = (@a = a + b + c + d + e); attr_reader :a; end
class Kw; def initialize(x, k: 1, **rest) = (@a = [x, k, rest]); attr_reader :a; end
class Opt; def initialize(x = 7, *more) = (@a = [x, more]); attr_reader :a; end
class Own
  def self.new(*args) = "own new #{args.inspect}"
end
class Kid < P2; end
class Plain; end
def make(k, *args) = k.new(*args)
p P0.new.a, P2.new(1, 2).a, P5.new(1, 2, 3, 4, 5).a, Kw.new(1, k: 2, z: 3).a, Kw.new(0).a
p Opt.new.a, Opt.new(1, 2, 3).a, Own.new(1), Kid.new(3, 4).a, Plain.new.class
args = [8, 9]
p P2.new(*args).a, make(P2, 5, 6).a, make(Own, 5).class, make(Kid, 1, 1).class
p P2.new(1, 2).a.equal?(P2.new(1, 2).a)
begin
  P2.new(1)
rescue ArgumentError => e
  p e.message
end
begin
  Plain.new(1)
rescue ArgumentError => e
  p e.message
end
class Boom
  def initialize(x)
    raise "boom #{x}" if x > 1
  end
end
3.times do |i|
  Boom.new(i)
  p i
rescue => e
  p e.message, e.backtrace.first[/in '.*'/], e.backtrace[1][/in '.*'/]
end
objs = 3.times.map { |i| P2.new(i, i) }
class P2
  def initialize(x, y) = (@a = x * y)
end
objs += 3.times.map { |i| P2.new(i, 3) }
p objs.map(&:a)
class Plain
  private_class_method :new
end
begin
  Plain.new
rescue NoMethodError => e
  p e.message
end
class Class
  alias_method :old_new, :new
  def new(*args) = "Class#new of #{self} #{args.inspect}"
end
p P0.new, P2.new(1, 2)
class Class
  alias_method :new, :old_new
end
p P0.new.a
begin
  Integer.new
rescue NoMethodError => e
  p e.message
end
S = Struct.new(:x, :y)
D = Data.define(:x)
p S.new(1, 2).to_a, D.new(x: 1).x, Class.new(Array).new(2, 0)
GC.start
many = 20_000.times.map { |i| P2.new(i, 1) }
GC.start
p many.sum(&:a), many.last.a
