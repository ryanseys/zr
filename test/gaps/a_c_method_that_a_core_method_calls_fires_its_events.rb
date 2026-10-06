# ruby fires :c_call and :c_return for a C method that another C method
# calls (rb_funcall): Class#new's initialize, and the method_missing that
# a Ruby method_missing reaches with super. zr's core methods fire no
# events for the calls they make.
class Plain; end
class Answering
  def method_missing(name, *) = name == :hello ? :hi : super
  def respond_to_missing?(*) = true
end
events = []
TracePoint.new(:c_call, :c_return) { |tp| events << [tp.event, tp.method_id] }.enable do
  Plain.new { }
  Answering.new.nope rescue nil
end
events.each { p _1 }
