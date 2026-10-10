# Data.define: immutable value classes.
Point = Data.define(:x, :y) do
  def dist = x + y
end
a = Point.new(1, 2)
b = Point.new(x: 1, y: 2)
p a, b, a == b, a.eql?(b), a.hash == b.hash, a.equal?(b), a.x, a.dist, a.frozen?, a.to_h, a.members, Point.members, a.inspect, a.to_s
p a.with(y: 5), a.with, Point.instance_methods(false).sort, Point.singleton_methods(false).sort, Data.instance_methods(false).sort, Point.superclass, Point.ancestors.first(2)
p a.deconstruct_keys([:x]), a.deconstruct_keys(nil), a.respond_to?(:deconstruct), a.instance_variables
begin; Point.new(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Point.new(1, 2, 3); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Point.new(x: 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Point.new(x: 1, y: 2, z: 3); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Point.new(1, y: 2); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; a.with(1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; a.with(z: 1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; a.instance_variable_set(:@x, 9); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Data.new; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Data.define(:a, :a); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Data.define("a"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Data.define(:x=); rescue => e; puts "#{e.class}: #{e.message}"; end
Empty = Data.define
p Empty.new, Empty.new.to_h, Empty.members, Empty.new == Empty.new
Named = Data.define(:v) do
  def initialize(v: 0) = super(v: v * 2)
end
p Named.new, Named.new(v: 2), Named.new(3)
D3 = Data.define(:a, :b, :c)
p D3.new(1, 2, 3).with(b: 9), D3[1, 2, 3], D3.new(a: 1, b: 2, c: 3).inspect
class Sub < Point; def sum = x + y; end
p Sub.new(1, 2), Sub.new(1, 2).sum, Sub.members
p Data.define(:x).new(1).inspect, Data.define(:x).new(1).class.name
r = Point.new(1, 2)
p r.to_h { |k, v| [k.to_s, v] }
p(Point.new(1, 2) == Point.new(2, 1))
h = { Point.new(1, 2) => :v }
p h[Point.new(1, 2)]
class Named
  def initialize(v: 0) = raise("nope") if false
end
Boom = Data.define(:q) do
  def initialize(q:)
    raise ArgumentError, "bad q" if q < 0
    super
  end
end
begin; Boom.new(-1); rescue => e; puts e.backtrace; end
begin; Boom.new(q: -1); rescue => e; puts e.backtrace; end
p Boom.new(1)
