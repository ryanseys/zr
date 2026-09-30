# `.to_i` on a receiver whose type is only known at run time gives
# the Integer value, not 0.
#
# Shape: a heterogeneous Hash returns a value of unknown type;
# `.to_i` on that.

class C
  def initialize
    @h = { "a" => 42, "b" => "hello" }
  end
  def at(k)
    (@h[k]).to_i
  end
end

c = C.new
puts c.at("a")
