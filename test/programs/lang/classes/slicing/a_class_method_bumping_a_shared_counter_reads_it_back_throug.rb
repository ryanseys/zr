# ClassVariableReadNode -- `@@var`, plus expression-form
# ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
# path) and several real-world class-var idioms.
#
# This test uses only class variables inside one class. It does not
# read a class variable across a class hierarchy.

# 1. Singleton-counter idiom: class-method bumps a shared counter,
#    instance-method reads it. Both methods use the same @@count.
class Counter
  @@count = 0

  def self.tick
    @@count = @@count + 1   # expression-form ClassVariableWriteNode
  end

  def self.value
    @@count                  # plain ClassVariableReadNode
  end

  def instance_value
    @@count                  # readable from instance methods too
  end
end

puts Counter.value           # 0
Counter.tick
Counter.tick
Counter.tick
puts Counter.value           # 3
puts Counter.new.instance_value   # 3 -- instance reads same slot


