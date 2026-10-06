# ruby compiles `new` to opt_new, which calls initialize with no
# :c_call for Class#new, except where a block is given.
class Foo
  def bar; end
  def initialize(a = 1) = @a = a
end
class Plain; end
events = []
set_trace_func(proc { |ev, _f, line, id, _b, klass| events << [ev, line, id, klass] if ev.start_with?("c-") || ev == "call" || ev == "return" })
Foo.new.bar
Plain.new
Foo.new(2) { }
set_trace_func(nil)
events.each { p _1 }
