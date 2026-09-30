# ClassVariableReadNode -- `@@var`, plus expression-form
# ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
# path) and several real-world class-var idioms.
#
# This test uses only class variables inside one class. It does not
# read a class variable across a class hierarchy.

# 5. Cvar mutation across instance and class methods of the same
#    class. Real Ruby code mixes these freely (e.g. ActiveRecord
#    counter caches).
class Registry
  @@items = 0

  def self.count
    @@items
  end

  def register
    @@items = @@items + 1
  end
end

r = Registry.new
r.register
r.register
puts Registry.count          # 2
