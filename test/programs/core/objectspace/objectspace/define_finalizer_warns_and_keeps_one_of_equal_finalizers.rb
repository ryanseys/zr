# ObjectSpace.define_finalizer: a finalizer bound to the object warns,
# and a finalizer equal to one already defined is not added again.
class HoldsSelf
  def initialize
    ObjectSpace.define_finalizer(self, method(:finalize))
  end

  def finalize(_id) = puts("finalizer run")
end
HoldsSelf.new

obj = Object.new
handler = proc { |_id| print "ok\n" }
first = ObjectSpace.define_finalizer(obj, handler)
again = ObjectSpace.define_finalizer(obj, handler.dup)
p first[1].equal?(handler), again[1].equal?(handler)
