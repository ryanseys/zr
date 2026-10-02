# defined? on a call chain tests the arguments first, then the receiver,
# and evaluates each receiver once: the call that its own test needed is
# the value of the next receiver, as ruby's defined_expr keeps it.
class Emp
  def me
    puts "me"
    self
  end

  def work = 1
  def boom = raise("no")
  def arg(x) = x
  def self_hid = defined?(self.hid.succ)

  private

  def hid = 2
end

e = Emp.new
p defined?(e.me.me.work)
p defined?(e.me.nope.work)
p defined?(e.boom.succ)
p defined?(e.me.arg(e.me))
p defined?(e.me.arg(zz))
p e.self_hid
p defined?(e&.me&.work)
x = nil
p defined?(x.to_s.size)
