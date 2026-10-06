# A TracePoint enabled with a method target sees only that method's own
# code: not Integer#times, which CRuby writes in Ruby, nor the methods it
# calls.
def target1
  a = 1
  b = 2
  1.times {
    3
  }
  [1].each { |x| x }
  4
end
def other = target1
%i[call line b_call return].each do |kinds|
  ev = []
  TracePoint.new(kinds, :return) { |tp| ev << [tp.event, tp.method_id] }.enable(target: method(:target1)) do
    target1
    other
  end
  p ev
end
