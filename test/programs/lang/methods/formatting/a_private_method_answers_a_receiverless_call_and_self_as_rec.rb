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

try("R.new.on_self") { R.new.on_self }
try("R.new.bare") { R.new.bare }
try("R.new.through_local") { R.new.through_local }
try("R.new.on_other(R.new)") { R.new.on_other(R.new) }
try("R.new.helper") { R.new.helper }
try("R.new.send(:helper)") { R.new.send(:helper) }
try("R.new.__send__(:helper)") { R.new.__send__(:helper) }
try("R.new.public_send(:helper)") { R.new.public_send(:helper) }
try("R.new.respond_to?(:helper)") { R.new.respond_to?(:helper) }
try("R.new.respond_to?(:helper, true)") { R.new.respond_to?(:helper, true) }

