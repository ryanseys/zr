# ruby's method_missing and const_missing are C methods that pop their
# frame before they raise: :c_call and :c_return, then :raise.
class Hidden
  private def secret = 1
end
events = []
TracePoint.new(:c_call, :c_return, :call, :return, :raise) { |tp|
  events << [tp.event, tp.method_id, tp.defined_class] if %i[method_missing const_missing].include?(tp.method_id) || tp.event == :raise
}.enable {
  missing_method_59398 rescue nil
  MISSING_CONSTANT_59398 rescue nil
  1.no_such rescue nil
  Hidden.new.secret rescue nil
  Comparable::NOPE rescue nil
}
events.each { p _1 }

# A method_missing that the program wrote is a Ruby method: :call and
# :return.
class Answering
  def method_missing(name, *) = name == :hello ? :hi : super
  def respond_to_missing?(*) = true
end
events.clear
TracePoint.new(:c_call, :c_return, :call, :return) { |tp|
  events << [tp.event, tp.method_id] if tp.method_id == :method_missing
}.enable { p Answering.new.hello }
events.each { p _1 }
