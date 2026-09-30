# A module class method resets a module-level hash ivar back to `{}`.
# Other writes give the hash Symbol keys and Integer values.
# The new empty hash has the same key and value types.
#
# Two checks in one shape:
#   1. The reset makes a hash of the right kind in a module (not a
#      class) method.
#   2. `@X` inside a module class method is the ivar of the module.

module Counters
  @counts = {}

  def self.add(name, n)
    @counts[name] = (@counts[name] || 0) + n
  end

  def self.fetch(name)
    @counts[name] || 0
  end

  def self.reset!
    @counts = {}
  end
end

Counters.add(:apples, 3)
Counters.add(:oranges, 5)
puts Counters.fetch(:apples)
puts Counters.fetch(:oranges)
Counters.reset!
puts Counters.fetch(:apples)
Counters.add(:apples, 7)
puts Counters.fetch(:apples)

# Array variant — same shape: module-level @list = [] in reset.
module Events
  @list = []

  def self.record(s)
    @list << s
  end

  def self.first
    @list[0] || ""
  end

  def self.reset!
    @list = []
  end
end

Events.record("one")
Events.record("two")
puts Events.first
Events.reset!
puts Events.first
Events.record("after_reset")
puts Events.first
