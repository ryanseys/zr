# Each exception's initialize returns the exception, as exc_initialize
# and its kin do. `p` writes rb_inspect of each object, and a trace sees
# that inspect.
names = %w[Exception StandardError RuntimeError ArgumentError NameError NoMethodError KeyError FrozenError
           NoMatchingPatternKeyError StopIteration SystemExit SignalException Interrupt SyntaxError LocalJumpError
           IOError EOFError TypeError ZeroDivisionError FloatDomainError RangeError RegexpError ThreadError
           FiberError EncodingError Encoding::CompatibilityError NotImplementedError ScriptError LoadError
           SecurityError SystemStackError NoMemoryError IndexError UncaughtThrowError ClosedQueueError]
names.each do |n|
  e = Object.const_get(n).allocate
  args = { "SignalException" => ["INT"], "UncaughtThrowError" => [1, 2] }.fetch(n, [])
  puts "#{n}: #{e.send(:initialize, *args).equal?(e)}"
end
e = SystemCallError.allocate
p e.send(:initialize, "m", 2).class
e = Errno::ENOENT.allocate
p e.send(:initialize).equal?(e)

p "é", "\xff".b, "é".encode("UTF-16LE"), :"é"
class Custom
  def inspect = "custom"
end
p Custom.new
Thread.new { p 1, "x" }.join

events = []
TracePoint.new(:c_call, :c_return) do |tp|
  events << [tp.event, tp.method_id, (tp.return_value.class if tp.event == :c_return)] if tp.path == __FILE__
end.enable do
  p 1
  p :s, "x"
  raise "m" rescue nil
end
events.each { p _1 }
