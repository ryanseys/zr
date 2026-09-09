Anon = Class.new do
  def hello = "hi from #{self.class}"
  X_IN_BLOCK = 1
end
p Anon.new.hello, Anon.name, Anon.superclass, defined?(X_IN_BLOCK), Anon.const_defined?(:X_IN_BLOCK) rescue p $!
Sub = Class.new(Anon) { def more = 2 }
p Sub.new.more, Sub.superclass, Sub.ancestors.first(2)
p Class.new.name, Class.new.superclass
begin
  Class.new(3)
rescue TypeError => e
  p e
end
Mod = Module.new do
  def modmeth = :m
end
p Mod.class, Mod.instance_methods, Mod.name
class Holder; end
Holder.class_eval do
  def added = :added
  attr_accessor :prop
end
p Holder.new.added, Holder.instance_methods(false).sort
Holder.class_exec(5) { |n| define_method(:five) { n } }
p Holder.new.five
o = Object.new
o.instance_eval { @secret = 42 }
p o.instance_variable_get(:@secret), o.instance_eval { @secret + 1 }
o.instance_eval do
  def only_me = :me
end
p o.only_me, o.singleton_methods
p 5.instance_eval { self + 1 }, o.instance_exec(2, 3) { |a, b| [self.class, a + b] }
r = Holder.class_eval { |k| k }
p r.equal?(Holder)
class Dyn
  define_method(:plain) { :plain }
  define_method(:args) { |a, b = 2, *r, k: 1| [a, b, r, k] }
  define_method(:returns) { return :early; :late }
  private define_method(:hidden) { :h }
  define_method(:from_method, instance_method(:plain))
  m = define_method(:sym) { }
  p m
end
d = Dyn.new
p d.plain, d.args(1), d.args(1, 3, 4, 5, k: 9), d.returns, d.from_method
p d.respond_to?(:hidden), d.send(:hidden)
begin
  d.args
rescue ArgumentError => e
  p e
end
p Dyn.instance_method(:args).parameters, Dyn.instance_method(:args).arity, Dyn.instance_method(:plain).arity
p d.method(:plain).owner, Dyn.instance_methods(false).sort
p Dyn.instance_method(:args).source_location.last
begin
  Dyn.class_eval { define_method(:noblock) }
rescue ArgumentError => e
  p e
end
begin
  Dyn.class_eval { define_method(:bad, 3) }
rescue TypeError => e
  p e
end
class Dyn
  define_method(:raiser) { raise "in bmethod" }
end
begin
  d.raiser
rescue => e
  puts e.backtrace
end
begin
  Class.new { raise "in class body" }
rescue => e
  puts e.backtrace
end
klass = Class.new(StandardError)
begin
  raise klass, "anon error"
rescue StandardError => e
  p e.message, e.class.superclass
end
p Class.new { }.new.class.class
counter = 0
Holder.class_eval { counter += 1 }
p counter
p(Holder.class_eval { self }, o.instance_eval { self }.equal?(o))
