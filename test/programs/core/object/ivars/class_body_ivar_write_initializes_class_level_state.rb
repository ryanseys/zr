# A bare `@x = ...` directly in a class body -- the ordinary way
# class-level state gets seeded. The write is kept, so the reader sees the
# value, not nil.

class Registry
  @items = []
  @count = 0
  def self.add(x); @items << x; @count += 1; self; end
  def self.items; @items; end
  def self.count; @count; end
end
Registry.add("a").add("b")
p Registry.items
p Registry.count
