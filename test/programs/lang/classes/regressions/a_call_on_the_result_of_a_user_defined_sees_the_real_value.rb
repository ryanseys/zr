# A call on the result of a user-defined `[]` (`.to_i`, `.length`)
# sees the real value that `[]` returns, here a String.

class T_issue219_aref_chain_Bag
  def initialize(h); @h = h; end
  def [](k); @h[k.to_sym]; end
end

bag = T_issue219_aref_chain_Bag.new({id: "42"})

# .to_i calls String#to_i.
puts bag[:id].to_i              # 42
puts bag[:id].to_i + 1          # 43

# .length calls String#length.
puts bag[:id].length            # 2

# The Integer goes into a method that adds to it.
class T_issue219_aref_chain_M
  def self.find(id); id + 1; end
end
puts T_issue219_aref_chain_M.find(bag[:id].to_i)      # 43

# A bag of Integer values: .to_s gives a String.
class T_issue219_aref_chain_IntBag
  def initialize(h); @h = h; end
  def [](k); @h[k]; end
end
ib = T_issue219_aref_chain_IntBag.new({n: 42})
puts ib[:n].to_s                # "42"
