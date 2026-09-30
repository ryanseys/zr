# ClassVariableReadNode -- `@@var`, plus expression-form
# ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
# path) and several real-world class-var idioms.
#
# This test uses only class variables inside one class. It does not
# read a class variable across a class hierarchy.

# 2. Per-class isolation: two unrelated classes with the same cvar
#    name each keep their own value. Counter.tick does not change
#    Other's count.
class Other
  @@count = 100

  def self.value
    @@count
  end
end

puts Other.value             # 100, unaffected by Counter.tick calls


