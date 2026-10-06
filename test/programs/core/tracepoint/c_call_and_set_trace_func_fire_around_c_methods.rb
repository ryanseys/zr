# TracePoint's :c_call and :c_return fire around each method CRuby
# writes in C, where the program calls it: an operator, an accessor, a
# method called with a block and the block's own calls.
class Point
  attr_reader :x

  def initialize = @x = 1
  def moved = x + 1
end

seen = []
point = Point.new
trace = TracePoint.new(:c_call, :c_return) do |tp|
  seen << [tp.event, tp.method_id, tp.defined_class, tp.self.class, tp.lineno, (tp.return_value if tp.event == :c_return)]
end
trace.enable
sum = 1 + 2
doubled = [1, 2].map { |v| v * 2 }
upper = "a".upcase
point.moved
sorted = [3, 1].sort
found = { a: 1 }[:a]
trace.disable
seen.each { |row| p row }
p [sum, doubled, upper, sorted, found]

# set_trace_func takes the same events and more, by their old names; a
# singleton method's class is its object, and a C method has no binding.
class Point
  def self.origin = new
end
hooked = []
set_trace_func proc { |event, file, line, id, binding, klass| hooked << [event, File.basename(file), line, id, binding.class, klass] }
Point.origin.moved
set_trace_func(nil)
# The hook's own set_trace_func calls are left out.
hooked.reject { |row| row[3] == :set_trace_func }.each { |row| p row }

