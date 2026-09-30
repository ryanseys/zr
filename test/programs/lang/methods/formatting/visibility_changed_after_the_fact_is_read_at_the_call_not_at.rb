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

# Visibility changed after the fact is a RUNTIME property, so a site that
# dispatches dynamically has to see the change. (A site whose receiver class is
# known at compile time answers from the compile-time table instead -- see
# tests/gaps/runtime_private_on_typed_receiver.rb.)
class Late
  def open_now = :open
end
try("Late#open_now before") { Late.new.open_now }
Late.send(:private, :open_now)
try("Late#open_now after") { [Late.new].first.open_now }
