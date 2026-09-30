# A call on a receiver of unknown type, where a user class also defines the
# method name. The builtin arm gives the builtin's own answer (here
# Hash#values), and the user arm gives the user method's answer. It takes one
# user definition to see it.
class Flash
  def initialize
    @h = { "a" => "b" }
  end

  def values = @h.values
  def keys = @h.keys
  def to_a = @h.to_a
end

def vals(x) = x.values
def ks(x) = x.keys
def entries(x) = x.to_a

p vals(Flash.new)
p vals({ a: 1 })
p ks(Flash.new)
p ks({ "c" => 2 })
p entries(Flash.new)
p entries({ "c" => 2 })
