# CRuby checks the arguments of a call as it sets up the callee's frame,
# before the frame is on the stack, so the :raise of a wrong count or of
# a wrong keyword is the caller's: its line and its method. The
# backtrace still starts in the callee.
def one(x) = x
def keyword(a: 1) = a
def required(a:) = a
def none(**nil) = nil

def caller_method
  one
rescue ArgumentError
  nil
end

events = []
TracePoint.new(:raise) { |tp| events << [tp.raised_exception.message, tp.lineno, tp.method_id] }.enable do
  one rescue nil
  one(1, 2) rescue nil
  keyword(b: 1) rescue nil
  keyword(b: 1, c: 2) rescue nil
  required rescue nil
  none(a: 1) rescue nil
  caller_method
  GC.start(foo: 1) rescue nil
  1.times(2) rescue nil
  [1].first(1, 2) rescue nil
  Integer() rescue nil
  [].fetch rescue nil
end
events.each { p _1 }

begin
  one
rescue ArgumentError => e
  p e.backtrace_locations.first(2).map { [_1.lineno, _1.label] }
end
