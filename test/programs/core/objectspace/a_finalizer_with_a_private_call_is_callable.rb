# define_finalizer takes any object that answers call, a private one too,
# and names the class of one that does not. The finalizers run as the
# program ends; the objects stay alive until then.
fin = Object.new
class << fin
  private def call(id) = puts("finalized private")
end
KEEP = [[], []]
ObjectSpace.define_finalizer(KEEP[0], fin)
pub = Object.new
def pub.call(id) = puts("finalized public")
ObjectSpace.define_finalizer(KEEP[1], pub)
c = Class.new
Object.const_set(:"C\u{3042}", c)
begin
  ObjectSpace.define_finalizer(Object.new, c.new)
rescue ArgumentError => e
  p e.message.sub(/0x\h+/, "X"), e.message.encoding
end
begin
  ObjectSpace.define_finalizer(Object.new, Object.new)
rescue ArgumentError => e
  p e.message
end
p ObjectSpace.define_finalizer(Object.new) { }.size
