# A C method of CRuby raises with rb_raise: rb_exc_new_str makes the
# error with `initialize`, and rb_exc_raise sends it `exception` and
# `backtrace`. KeyError and NameError are made with no `initialize`.
def c_calls
  seen = []
  TracePoint.new(:c_call) { |tp| seen << "#{tp.defined_class}##{tp.method_id}" if tp.path == __FILE__ }.enable { yield }
  seen
end

p c_calls { 1 / 0 rescue nil }
p c_calls { [].fetch(3) rescue nil }
p c_calls { {}.fetch(:a) rescue nil }
p c_calls { [1].first(-1) rescue nil }
p c_calls { "a" * -1 rescue nil }
p c_calls { :a.unknown rescue nil }
p c_calls { Object.const_get(:Nope) rescue nil }

# A method that CRuby writes in Ruby raises at its <internal:...> path.
p c_calls { Integer("x") rescue nil }

# A raise of the program's own sends `exception` to the class.
p c_calls { raise IndexError, "m" rescue nil }

# An `initialize` that the program writes for a core error runs for the
# errors that core methods make, as rb_class_new_instance finds it.
class ZeroDivisionError
  def initialize(message) = super("zero: #{message}")
end

class IndexError
  def initialize(message) = super("index: #{message}")
end

class TypeError
  def initialize(*args) = super("type: #{args.inspect}")
end

class KeyError
  def initialize(*) = super("never runs")
end

p((1 / 0 rescue $!.message))
p(([].fetch(3) rescue $!.message))
p(([1].first(-1) rescue $!.message))
p((1 + nil rescue $!.message))
p((Integer(nil) rescue $!.message))
p(({}.fetch(:a) rescue $!.message))
