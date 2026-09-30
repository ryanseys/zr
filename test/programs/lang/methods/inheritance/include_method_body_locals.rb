# A module instance method with body locals, included into a user class.
# The method runs on an instance of the class, and its body locals (`found`,
# `doubled`) work as in any method. The helper lives on a separate class so
# its return type resolves cleanly (the check is the included method's own
# body locals, not the callee).
class Result
  def initialize(v)
    @v = v
  end
  def v
    @v
  end
end

class Factory
  def self.make(n)
    Result.new(n * 2)
  end
end

module Dispatcher
  def run(n)
    found = Factory.make(n)   # object-typed local, declared in the clone
    doubled = found.v
    doubled + 1
  end
end

class Runner
  include Dispatcher
end

puts Runner.new.run(5).to_s
