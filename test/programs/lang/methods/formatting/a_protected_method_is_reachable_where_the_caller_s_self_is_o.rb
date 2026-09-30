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

# `protected` is the receiver-sensitive one: reachable when the CALLER's self
# is a kind of the method's owner, whoever the receiver is.
class Money
  def >(other) = amount > other.amount
  protected def amount = 7
end
class Cash < Money; end
class Outsider
  def peek(m) = m.amount
end

try("Money.new > Money.new") { Money.new > Money.new }
try("Money.new > Cash.new") { Money.new > Cash.new }
try("Cash.new > Money.new") { Cash.new > Money.new }
try("Outsider.new.peek(Money.new)") { Outsider.new.peek(Money.new) }
try("Money.new.amount") { Money.new.amount }
try("Money.new.send(:amount)") { Money.new.send(:amount) }
try("Money.new.public_send(:amount)") { Money.new.public_send(:amount) }

