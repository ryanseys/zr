# Two unrelated classes each define `def get(k)` with different
# return types. `r = c.get("/foo")` calls IntClient#get, so `r` is
# an IntBag, not the String that StrBag#get returns.

class T_imeth_name_collision_recv_aware_StrBag
  def initialize
    @h = {"a" => "b"}
    @h.delete("a")
    @h["x"] = "got-x"
  end
  def get(k)
    @h[k]
  end
end

class T_imeth_name_collision_recv_aware_IntBag
  attr_accessor :status
  def initialize
    @status = 42
  end
end

class T_imeth_name_collision_recv_aware_IntClient
  def get(path)
    out = T_imeth_name_collision_recv_aware_IntBag.new
    out.status = path.length
    out
  end
end

s = T_imeth_name_collision_recv_aware_StrBag.new
puts s.get("x")

c = T_imeth_name_collision_recv_aware_IntClient.new
r = c.get("/foo")
puts r.status
