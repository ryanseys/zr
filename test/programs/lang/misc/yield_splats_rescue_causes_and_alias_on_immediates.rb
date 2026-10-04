# yield(*args) passes a ruby2_keywords Hash as keywords, a raise in a rescue
# clause's class list has the raise as its cause, $@ = nil empties the
# backtrace, and alias or undef in 1.instance_eval has no class to change.
def t(*a, **k) = [a, k]
ruby2_keywords def r(*a) = a
args = r(a: 1)
def y1(args) = yield(*args)
p y1(args) { |*a, **k| [a, k] }
p y1(args, &->(*a, **k) { [a, k] })
p y1(args, &proc { |*a, **k| [a, k] })
p t(*args)
p proc { |*a, **k| [a, k] }.call(*args)
p ->(*a, **k) { [a, k] }.call(*args)
def y2(args) = yield(1, *args)
p y2(args) { |*a, **k| [a, k] }
p y2(args, &->(*a, **k) { [a, k] })
runner = Object.new
runner.singleton_class.define_method(:`) { |str| p [str, str.frozen?] }
runner.instance_exec { `test command` }
runner.instance_exec { %x{test command} }
begin
  1.instance_eval { alias :foo :to_s }
rescue TypeError => e
  p e.message
end
begin
  :blah.instance_eval { alias :foo :to_s }
rescue TypeError => e
  p e.message
end
begin
  begin
    raise "from block"
  rescue (raise "from rescue expression")
  end
rescue => e
  p [e.message, e.cause&.message]
end
begin
  raise "x"
rescue
  $@ = nil
  p $@
end
begin
  1.instance_eval { undef :to_s }
rescue TypeError => e
  p e.message
end
def again(e) = raise(e)
begin
  raise "first"
rescue => e
  e.set_backtrace(nil)
  p [e.backtrace, e.backtrace_locations.size]
end
begin
  again(e)
rescue => e2
  p e2.backtrace.size == e2.backtrace_locations.size
end
