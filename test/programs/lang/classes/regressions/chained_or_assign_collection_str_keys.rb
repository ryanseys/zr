# Same chained `||=`, but on a Hash with String keys.

class T_chained_or_assign_collection_str_keys_C
  def initialize
    @h = {}
    @h["init"] = []      # a String key with an Array value
  end
  def add(k, v)
    (@h[k] ||= []) << v
  end
  def count(k); @h[k].length; end
end

c = T_chained_or_assign_collection_str_keys_C.new
c.add("init", 7)         # appends to existing
c.add("foo", 1)
c.add("foo", 2)
c.add("bar", 100)
puts c.count("init")     # 1
puts c.count("foo")      # 2
puts c.count("bar")      # 1
