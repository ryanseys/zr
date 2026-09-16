# A method define_method makes allocates nothing per call: its body runs
# as a stack image of the block under the receiver, and the block the
# call was given reaches it through the frame.
class Base
  def greet(x) = "base #{x}"
end

class Kid < Base
  define_method(:greet) { |x| "kid " + super(x) }
  define_method(:with_block) { |&b| [block_given?, b ? b.call(1) : :none] }
  define_method(:defines) { def made = :made; self.class.instance_methods(false).sort }
  define_method(:early) { |n| return :early if n.zero?; :late }
  define_method(:each_twice) { |&b| b.call(1); b.call(2); :done }
  define_method(:lam, ->(a, b = 2) { [a, b] })
  pr = proc { |a| a }
  define_method(:pro, pr)
  alias_method :greet2, :greet
end

k = Kid.new
p k.greet(1), k.greet2(2)
p k.with_block { |v| v + 1 }, k.with_block
p k.defines
p k.early(0), k.early(1)
p k.each_twice { |v| break :broke if v == 2 }
p k.each_twice { |v| next :skip }
p k.lam(1), k.lam(1, 3)
p((k.lam rescue $!.class))
p k.pro(5), (k.pro rescue $!.class)
m = k.method(:with_block)
p m.call { 7 }, m.unbind.bind(Kid.new).call { 8 }
p k.method(:greet) == k.method(:greet2), k.method(:greet).hash == k.method(:greet).hash
p m.arity, m.parameters, k.method(:lam).parameters, k.method(:greet).owner
events = []
tp = TracePoint.new(:call, :return) { |t| events << [t.event, t.method_id, t.lineno] if t.method_id == :early }
tp.enable { k.early(0); k.early(1) }
p events
def looped(k)
  i = 0
  total = 0
  while i < 20000
    total += k.lam(i).last
    total += k.greet(i).size
    i += 1
  end
  total
end
p looped(k)
p k.singleton_class.instance_method(:greet).owner
class Kid
  define_method(:greet) { |x| "again " + x.to_s }
end
p k.greet(3), k.greet2(3)

__END__
"kid base 1"
"kid base 2"
[false, 2]
[false, :none]
[:defines, :each_twice, :early, :greet, :greet2, :lam, :made, :pro, :with_block]
:early
:late
:broke
:done
[1, 2]
[1, 3]
ArgumentError
5
ArgumentError
[false, 7]
[false, 8]
true
true
0
[[:block, :b]]
[[:req, :a], [:opt, :b]]
Kid
[[:call, :early, 12], [:return, :early, 12], [:call, :early, 12], [:return, :early, 12]]
308890
Kid
"again 3"
"kid base 3"
