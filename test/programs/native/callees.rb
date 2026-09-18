# __callee__ through aliases, caller_locations, singleton_class?, SignalException, and slice!.
class Greeter
  def hello = [__method__, __callee__]
  alias hi hello
  def nested = [1].map { [__method__, __callee__] }.first
  alias nested2 nested
  def self.make = [__method__, __callee__]
  class << self
    alias build make
  end
end
g = Greeter.new
p g.hello, g.hi, g.nested, g.nested2, Greeter.make, Greeter.build, __callee__, __method__
def top = __callee__
alias top2 top
p top, top2, [1].each { break __callee__ }

def where = caller_locations
def outer_where = where
locs = outer_where
p locs.class, locs.first.class, locs.first.path, locs.first.lineno, locs.first.label, locs.first.base_label, locs.first.to_s, locs.first.inspect, locs.size, locs.first.absolute_path
def where0 = caller_locations(0)
p where0.first.label, where0.first.lineno
def limited = caller_locations(1, 1)
p limited.size, caller_locations(9)
[1].each { p caller_locations(0).first.base_label, caller_locations(0).first.label }
p Greeter.singleton_class?, Greeter.singleton_class.singleton_class?, Module.new.singleton_class?, g.singleton_class.singleton_class?, Kernel.singleton_class?

p SignalException.new("INT").signo, SignalException.new("INT").message, SignalException.new(2).message, SignalException.new("SIGTERM").signo, Interrupt.new.message, Interrupt.new.signo, Interrupt.new("custom").message, SignalException.new(15, "x").message, SignalException.new("INT").signm, Interrupt.superclass, SignalException.superclass
begin; SignalException.new("NOPE"); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; SignalException.new; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; SignalException.new(99); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; raise Interrupt; rescue Interrupt => e; p e.message, e.signo; end

s = +"hello world"
p s.slice!(0), s, s.slice!(1, 3), s, s.slice!("wor"), s, s.slice!(20), s.slice!(-2..), s, s.slice!("zzz"), s.slice!(1..1), s
a = [1, 2, 3, 4, 5]
p a.slice!(1), a, a.slice!(1, 2), a, a.slice!(0..0), a, a.slice!(9), a
