# ClassVariableReadNode -- `@@var`, plus expression-form
# ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
# path) and several real-world class-var idioms.
#
# This test uses only class variables inside one class. It does not
# read a class variable across a class hierarchy.

# 4. Cvar updated across many class-method calls -- the cumulative
#    state lives in the cvar, not in any temporary. The test calls
#    `add` once for each value, with no chain.
class Tally
  @@total = 0

  def self.add(n)
    @@total = @@total + n
  end

  def self.total
    @@total
  end
end

Tally.add(10)
Tally.add(20)
Tally.add(12)
puts Tally.total             # 42


