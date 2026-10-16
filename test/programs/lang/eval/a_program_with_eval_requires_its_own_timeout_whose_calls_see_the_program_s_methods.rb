require "timeout"

# A program that evals carries eval's compiler, which prism's
# ruby_parser translation would bring timeout into. The program's
# timeout is still its own: its calls see the methods that the program
# defines, as test_timeout's mock scheduler has it.
p eval("1 + 1")

def with_scheduler(mock)
  original = Fiber.method(:current_scheduler)
  Fiber.singleton_class.remove_method(:current_scheduler)
  Fiber.define_singleton_method(:current_scheduler) do
    puts "current_scheduler"
    mock
  end
  yield
ensure
  Fiber.singleton_class.remove_method(:current_scheduler)
  Fiber.define_singleton_method(:current_scheduler, original)
end

mock = Object.new
mock.define_singleton_method(:timeout_after) do |sec, exc, message, &block|
  p [:timeout_after, sec, exc.class, message]
  block.call(sec)
end
with_scheduler(mock) { p Timeout.timeout(5) { :ok } }

custom = Class.new(StandardError)
mock.define_singleton_method(:timeout_after) do |sec, exc, message, &block|
  p [:custom, sec, exc == custom, message]
  raise exc, message
end
with_scheduler(mock) do
  Timeout.timeout(1, custom, "custom message") { :never }
rescue custom => e
  p [:raised, e.message]
end

p Fiber.current_scheduler
p Timeout.timeout(5) { :after }
begin
  Timeout.timeout(0.01) { sleep 1 }
rescue Timeout::Error => e
  p [e.class, e.message]
end

# A method that the program defines on a class that timeout calls.
def Process.clock_gettime(*args)
  @calls = (@calls || 0) + 1
  super
end
Timeout.timeout(5) { :timed }
p Process.instance_variable_get(:@calls).to_i.positive?
p $LOADED_FEATURES.grep(/timeout/).map { File.basename(_1) }
