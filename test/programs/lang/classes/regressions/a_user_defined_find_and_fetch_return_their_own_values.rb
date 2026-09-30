# A user-defined `find` or `fetch` returns the value of its own body
# (a String here), not the value of the built-in method with that
# name.

# Class method form (canonical ActiveRecord finder shape).
class T_issue204_user_find_fetch_Bag
  def self.find(id); "row-#{id}"; end
  def self.fetch(id); "fetched-#{id}"; end
end
puts T_issue204_user_find_fetch_Bag.find(42)        # row-42
puts T_issue204_user_find_fetch_Bag.fetch(99)       # fetched-99

# Instance method form on a hash-wrapping class.
class T_issue204_user_find_fetch_C
  def initialize(h); @h = h; end
  def find(key); @h[key.to_sym]; end
  def fetch(key); @h[key.to_sym]; end
end
c = T_issue204_user_find_fetch_C.new({a: "alpha", b: "beta"})
puts c.find(:a)          # alpha
puts c.fetch(:b)         # beta

# The built-in Array#find still works.
puts ["x", "y", "z"].find { |v| v == "y" }   # y
