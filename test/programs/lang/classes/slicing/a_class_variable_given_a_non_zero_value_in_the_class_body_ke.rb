# ClassVariableReadNode -- `@@var`, plus expression-form
# ClassVariableWriteNode (the `@@x = ...` last-expression-as-return
# path) and several real-world class-var idioms.
#
# This test uses only class variables inside one class. It does not
# read a class variable across a class hierarchy.

# 3. Cvar with explicit non-zero initial value at class body. The
#    cvar has the value from the source, not a type default.
class Config
  @@debug = true
  @@max_retries = 5

  def self.debug?; @@debug; end
  def self.max_retries; @@max_retries; end
end

puts Config.debug?           # true
puts Config.max_retries      # 5


