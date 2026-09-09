# native only: fibers and Process.times
# Struct, Data, method_missing, enumerable and fiber storage rules.
class Sack
  include Enumerable
  def each(&b) = [1].each(&b)
  def method_missing(name, *a) = "mm:#{name}"
end
puts Sack.new.nope
class Bag
  include Comparable
  def method_missing(name, *a) = "mm:#{name}"
end
puts Bag.new.nope
class Plain
  def method_missing(name, *a) = "mm:#{name}"
end
puts Plain.new.nope
class Ghost
  def method_missing(name, *args, **kw, &blk)
    return super unless name.to_s.start_with?("g_")
    [name, args, kw, blk&.call]
  end
  def respond_to_missing?(name, priv = false) = name.to_s.start_with?("g_") || super
end
g = Ghost.new
p g.g_x(1, 2, k: 3) { 4 }
p g.respond_to?(:g_y), g.respond_to?(:other)
begin; g.other; rescue NoMethodError => e; puts e.message; p e.name, e.args; end
p g.method(:g_z).call(9)
p (g.g_w rescue $!)
o = Object.new
begin; o.method_missing(:zz); rescue NoMethodError => e; puts e.message; end
p Object.new.respond_to?(:respond_to_missing?), Object.private_instance_methods.include?(:respond_to_missing?)
p BasicObject.private_instance_methods(false).sort.first(3)
l = [1,2,4,5,7].lazy.chunk_while { |a,b| b-a==1 }; p l.class; p l.to_a
c = [1,2,3].lazy.chunk { |x| x.odd? }; p c.to_a
p [1,2,3].lazy.slice_before { |x| x == 2 }.to_a
p [1,2,3].lazy.slice_when { |a,b| b > a }.first(1)
p [1,2,3].lazy.slice_after(2).to_a
p (1..Float::INFINITY).lazy.slice_when { |a, b| b % 3 == 0 }.first(2)
p([1, 1, 2].each.uniq)
p([10, 20, 30].lazy.with_index.to_a)
p [1,2,3].chunk { |x| x == 2 ? :_separator : x.odd? }.to_a
p [1,2,3].chunk { |x| x == 2 ? :_alone : true }.to_a
p [1,2,3].chunk { |x| x == 2 ? nil : true }.to_a
begin; [1].chunk { |x| :_bad }.to_a; rescue => e; p e; end
p [1,2,3].chunk.class
p [].slice_when { |a,b| true }.to_a, [].chunk_while { true }.to_a
p [1,2,4,5].slice_before { |x| x.even? }.to_a, [1,2,4,5].slice_after(&:even?).to_a, [1,2,4,5].slice_after(4).to_a
p (1..Float::INFINITY).lazy.chunk { |x| x / 3 }.first(2)
p Fiber[:a]; Fiber[:a] = 1; p Fiber[:a], Fiber.current.storage
f = Fiber.new { Fiber[:a] }; p f.resume
f2 = Fiber.new(storage: {b: 2}) { [Fiber[:a], Fiber[:b]] }; p f2.resume
f3 = Fiber.new(storage: nil) { Fiber[:a] }; p f3.resume
begin; Fiber["s"]; rescue => e; p e; end
x = (Fiber[:n] = 42); p x
Fiber[:c] = Fiber[:d] = 7; p Fiber[:c], Fiber[:d]
Fiber.current.storage = {c: 3}; p Fiber[:a], Fiber[:c]
p Fiber.new { 5 }.resume
p Fiber.respond_to?(:new)
begin; Fiber[1]; rescue => e; p e; end
Fiber["s"] = 9; p Fiber[:s]
S = Struct.new(:verbose?, :name)
p S.new(true, "x"), S.new(true, "x").each_pair.to_a
p Struct.new.new, Data.define.new, Struct.new("Tms2", :a).new(1)
K = Struct.new(:a, keyword_init: true)
p K, K.inspect, K.to_s, K.new(a: 1)
D = Data.define(:m)
class NoSuper < D
  def initialize(**kw) = @z = 1
end
o = NoSuper.new(m: 1); p [o.frozen?, o.m]
class AfterSuper < D
  def initialize(**kw)
    super
    @z = 1
  end
end
begin; AfterSuper.new(m: 1); rescue => e; p e.class, e.message; end
P = Data.define(:x, :y)
a = P.new(1, 2); p a.dup.frozen?, a.clone(freeze: false).frozen?
C = Data.define(:class, :hash); c = C.new("k", 5); p c.class, c.hash, c.inspect
p S.instance_method(:"verbose?=").parameters, D.instance_method(:m).parameters
t = Process.times; p t.class, t.utime.class, t.cstime >= 0.0
class Symbol; def inspect = "S" + super; end
p :a.inspect.sub(/0x\h+/, "ADDR")
p [3, 1, 2].minmax { |x, y| x <=> y }, [5, 1].minmax, [].minmax
p((-0.0).round(3), (-0.0001).round(2), 2.upto(9).size, 9.downto(2).size, "az".next)
begin; [1].count(1, 2); rescue ArgumentError => e; p e.message; end
p [1, 2, 1].count(1), [1, 2].count { |x| x > 1 }, [1, 2].count
p [1, 2].each.to_s.sub(/0x\h+/, "ADDR"), [1, 2].lazy.to_s.sub(/0x\h+/, "ADDR")
g = Enumerator.new { |y| got = y.yield(10); y << (got * 2) }
p g.next; g.feed(5); p g.next
begin; [1.0, Float::NAN].sort_by { |x| x }; rescue ArgumentError => e; p e.message; end
begin; [1, "a"].min_by { |x| x }; rescue ArgumentError => e; p e.message; end
h = { "a" => 1 }
for h["k"] in [7]; end
p h
for q, r in [[1, 2, 3]].each; end
p [q, r]
class Two; def each; yield 1, 2; end; end
for u, v in Two.new; end
p [u, v]
p ENV.each_value.class, ENV.each_key.first.class
