# Module-level @ivar referenced inside `def self.X` (the canonical
# Ruby singleton-state pattern). Each write form, and the read, uses
# the ivar of the module object.
#
# Coverage:
#   - Plain `@count += 1` (InstanceVariableOperatorWriteNode).
#   - `@count = N` (InstanceVariableWriteNode).
#   - `@flag ||= true` (InstanceVariableOrWriteNode).
#   - Read access via `@count` (InstanceVariableReadNode), by the
#     puts below.

module Counter
  @count = 0
  @flag = false

  def self.increment
    @count += 1
  end

  def self.reset
    @count = 0
  end

  def self.set_flag
    @flag ||= true
  end

  def self.value
    @count
  end

  def self.flag?
    @flag
  end
end

Counter.increment
Counter.increment
Counter.increment
puts Counter.value
Counter.set_flag
puts Counter.flag?
Counter.reset
puts Counter.value
