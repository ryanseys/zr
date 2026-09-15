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

__END__
[:c_call, :+, Integer, Integer, 17, nil]
[:c_return, :+, Integer, Integer, 17, 3]
[:c_call, :map, Array, Array, 18, nil]
[:c_call, :*, Integer, Integer, 18, nil]
[:c_return, :*, Integer, Integer, 18, 2]
[:c_call, :*, Integer, Integer, 18, nil]
[:c_return, :*, Integer, Integer, 18, 4]
[:c_return, :map, Array, Array, 18, [2, 4]]
[:c_call, :upcase, String, String, 19, nil]
[:c_return, :upcase, String, String, 19, "A"]
[:c_call, :x, Point, Point, 8, nil]
[:c_return, :x, Point, Point, 8, 1]
[:c_call, :+, Integer, Integer, 8, nil]
[:c_return, :+, Integer, Integer, 8, 2]
[:c_call, :sort, Array, Array, 21, nil]
[:c_return, :sort, Array, Array, 21, [1, 3]]
[:c_call, :[], Hash, Hash, 22, nil]
[:c_return, :[], Hash, Hash, 22, 1]
[3, [2, 4], "A", [1, 3], 1]
["line", "c_call_and_set_trace_func_fire_around_c_methods.rb", 34, nil, Binding, nil]
["call", "c_call_and_set_trace_func_fire_around_c_methods.rb", 30, :origin, Binding, Point]
["call", "c_call_and_set_trace_func_fire_around_c_methods.rb", 7, :initialize, Binding, Point]
["return", "c_call_and_set_trace_func_fire_around_c_methods.rb", 7, :initialize, Binding, Point]
["return", "c_call_and_set_trace_func_fire_around_c_methods.rb", 30, :origin, Binding, Point]
["call", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :moved, Binding, Point]
["c-call", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :x, NilClass, Point]
["c-return", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :x, NilClass, Point]
["c-call", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :+, NilClass, Integer]
["c-return", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :+, NilClass, Integer]
["return", "c_call_and_set_trace_func_fire_around_c_methods.rb", 8, :moved, Binding, Point]
["line", "c_call_and_set_trace_func_fire_around_c_methods.rb", 35, nil, Binding, nil]
