# ruby fires :c_call and :c_return for a C method that another C method
# calls (rb_funcall). zr fires them for the calls that stand for C's
# rb_funcall in Class#new, include, extend, the hooks, raise, super, p,
# inspect and the `each` of Enumerable. The NoMethodError that the base
# method_missing makes fires no `exception` or `backtrace`, and the calls
# inside an Enumerator (`each_slice(1).to_a`) differ.
class Plain; end
class Answering
  def method_missing(name, *) = name == :hello ? :hi : super
  def respond_to_missing?(*) = true
end
events = []
TracePoint.new(:c_call, :c_return) { |tp| events << [tp.event, tp.method_id] if tp.path == __FILE__ }.enable do
  Plain.new { }
  Answering.new.nope rescue nil
  p 1
end
events.each { p _1 }
