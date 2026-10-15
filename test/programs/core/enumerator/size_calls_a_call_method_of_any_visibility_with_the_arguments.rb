# Enumerator#size calls the size's `call` as rb_check_funcall does: a
# private method counts, method_missing answers when respond_to_missing?
# says so, and the call gets the enumerator's arguments.
o = Object.new
def o.each(*) = nil
p o.to_enum(:each, 5, 6) { |*a| a }.size
p o.enum_for(:each, 1, k: 2) { |*a, **kw| [a, kw] }.size
p Enumerator.new(3) { }.size, Enumerator.new(-> { 7 }) { }.size, Enumerator.new { }.size

class Sizer
  def respond_to_missing?(name, include_private = false) = name == :call
  def method_missing(name, *args) = name == :call ? [:missing, args] : super
end
p Enumerator.new(Sizer.new) { }.size

def call = "private Object#call"
p Enumerator.new { }.size, Enumerator.new(nil) { }.size

# Enumerator.new itself takes only a size that responds to a public call.
class Hidden
  private def call = :hidden
end
p((Enumerator.new(Hidden.new) { } rescue $!.class))
