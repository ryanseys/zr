# A subclass override that returns nil must still run when called
# through an ivar that can hold a Base or a Sub.
#
# Two checks:
#  1. The override's side effect runs (the `puts` inside T_poly_nil_return_dispatch_Sub#hook).
#  2. The call's *return value* is nil.

class T_poly_nil_return_dispatch_Base
  def hook(arg); end          # empty body -> returns nil
end

class T_poly_nil_return_dispatch_Sub < T_poly_nil_return_dispatch_Base
  def hook(arg)
    puts "subclass-ran: " + arg   # `puts` returns nil
  end
end

class T_poly_nil_return_dispatch_Holder
  attr_accessor :h
  def initialize; @h = T_poly_nil_return_dispatch_Base.new; end
  def set(x); @h = x; end
  def call_hook(arg); @h.hook(arg); end
end

h = T_poly_nil_return_dispatch_Holder.new
h.set(T_poly_nil_return_dispatch_Sub.new)
result = h.call_hook("ok")
puts result == nil
