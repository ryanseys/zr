# Ruby decides visibility from the SHAPE of the call, not from the value the
# receiver holds. `vm_call_method` runs no check at all for an implicit
# receiver, for the literal `self` keyword, or for `send` (all FCALL); every
# other explicit receiver is checked.
#
# zr enforced that only where the receiver's class was known at compile time.
# A dynamic call skipped it entirely, so `1.puts("x")` printed, `"ab".initialize`
# answered nil, and a private method reached through a local that merely HELD
# self went through.

def try(label)
  v = yield
  puts "#{label} => #{v.inspect}"
rescue NoMethodError => e
  puts "#{label} !! #{e.class}: #{e.message}"
end

class R
  def on_self = self.helper
  def bare = helper

  # A local holding `self` is an ordinary explicit receiver. Only the `self`
  # KEYWORD is exempt, which is why this one raises and `on_self` does not.
  def through_local
    me = self
    me.helper
  end

  def on_other(o) = o.helper
  private def helper = :helped
end

# The builtin rows answer the same way -- Kernel's methods are private, on
# every receiver, whatever its class.
try("1.puts") { 1.puts("x") }
try("'ab'.puts") { "ab".puts("x") }
try("nil.puts") { nil.puts("x") }
try("[].raise") { [].raise("boom") }
try("'ab'.initialize") { "ab".initialize }
try("[].initialize") { [].initialize }
try("Object.new.initialize") { Object.new.initialize }
try("RuntimeError.new.initialize") { RuntimeError.new.initialize }
try("3.7.require") { 3.7.require("set") }

