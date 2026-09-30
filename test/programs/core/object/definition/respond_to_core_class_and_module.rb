# respond_to? on a core class or module answers from that class's own methods,
# also on Thread / Mutex / Fiber. A module answers true for its module_function
# methods, but not for its plain instance methods.
r1 = (String.respond_to?(:new) rescue $!.class); p r1
r2 = (Integer.respond_to?(:sqrt) rescue $!.class); p r2
r3 = (Comparable.respond_to?(:new) rescue $!.class); p r3
p Thread.respond_to?(:new)
p Mutex.respond_to?(:new)
p Fiber.respond_to?(:new)
p Array.respond_to?(:new)
p Hash.respond_to?(:new)
p Math.respond_to?(:sqrt)
p Enumerable.respond_to?(:new)
p Float.respond_to?(:nonexistent_thing)

module Greeter
  def greet = "hi"
  def self.version = 1
  module_function
  def helper = 2
end
p Greeter.respond_to?(:version)
p Greeter.respond_to?(:greet)
p Greeter.respond_to?(:helper)
p Greeter.respond_to?(:missing)

class Host
  include Greeter
  def self.make = new
end
p Host.respond_to?(:make)
p Host.respond_to?(:greet)
p Host.respond_to?(:new)
p Host.new.respond_to?(:greet)
