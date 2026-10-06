# A core method that the program calls fires :c_call and :c_return for
# the C methods that it calls, as rb_funcall does in CRuby: Class#new's
# initialize, the hooks of Class.new, include, extend and the def
# methods, raise's exception and backtrace (after raise's own c_return),
# a super into a C method, and inspect's instance_variables_to_inspect.
class Bar; end
module M; end
class Loud
  def to_s = super
  def inspect(*) = super()
end

events = []
trace = TracePoint.new(:c_call, :c_return, :raise) do |tp|
  events << [tp.event, tp.method_id, tp.defined_class] if tp.path == __FILE__
end
trace.enable do
  Bar.new
  Bar.new { }
  Class.new(Bar)
  Bar.define_method(:q) { }
  Bar.include(M)
  Bar.extend(M)
  Bar.class_eval { def r; end }
  Module.new
  begin
    raise TypeError, "error"
  rescue TypeError
  end
  begin
    raise "plain"
  rescue
  end
  x = Loud.new
  x.to_s
  x.inspect
end
events.each { p _1 }

# A String alone makes its RuntimeError with `new`, so a program's
# initialize runs.
class RuntimeError
  alias_method :orig_init, :initialize
  def initialize(*args) = orig_init("wrapped: #{args.first}")
end
begin
  raise "changed"
rescue => e
  p e.message
end
