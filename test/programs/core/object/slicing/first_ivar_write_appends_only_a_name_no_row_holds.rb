# One write site shared by classes whose tables order names differently.
module Setter
  def set_b(v) = (@b = v)
  def set_a(v) = (@a = v)
end
class AB; include Setter; def initialize = (@a = 1; @b = 2); end
class BA; include Setter; def initialize = (@b = 3); end
class Empty; include Setter; end
objs = [AB.new, BA.new, Empty.new]
objs.each { |o| o.set_b(9); o.set_a(8); o.set_b(7) }
objs.each { |o| p [o.class, o.instance_variables, o.instance_variables.map { |n| o.instance_variable_get(n) }] }

# Seventy names: every bit of the filter collides.
class Many
  def initialize
    70.times { |i| instance_variable_set(:"@v#{i}", i) }
  end
  def again
    @v3 = :three
    @v67 = :sixty_seven
    @fresh = :fresh
    self
  end
end
m = Many.new.again
p m.instance_variables.size, m.instance_variables.uniq.size, m.instance_variable_get(:@v67), m.instance_variable_get(:@fresh)

# Removal, then the same name written again at a site.
class Removal
  def initialize = (@x = 1; @y = 2)
  def put_x(v) = (@x = v)
end
r = Removal.new
r.remove_instance_variable(:@x)
r.put_x(5)
r.put_x(6)
p r.instance_variables, r.instance_variable_get(:@x)

# dup and clone, then a first write on the copy.
class Pt
  def initialize = (@x = 1)
  def add_y = (@y = 2; self)
  def add_x = (@x = 10; self)
end
a = Pt.new
b = a.dup.add_y.add_x
c = a.clone.add_x.add_y
p a.instance_variables, b.instance_variables, c.instance_variables, b.instance_variable_get(:@x)

# Marshal round trip, then writes.
d = Marshal.load(Marshal.dump(Pt.new)).add_y.add_x
p d.instance_variables, d.instance_variable_get(:@x)

# Many objects through initialize, with a collection between.
class Node
  def initialize(v) = (@l = nil; @r = nil; @v = v; @t = "n"; @u = v * 2)
  attr_reader :v, :u, :t
end
nodes = Array.new(20_000) { |i| Node.new(i) }
GC.start
p nodes.sum(&:u), nodes.map(&:t).uniq, nodes[17].instance_variables

# A frozen object and a class's own ivars.
f = Pt.new.freeze
begin
  f.add_y
rescue => e
  p e.class
end
class Pt; @count = 1; def self.bump = (@count += 1; @other = 2); end
Pt.bump
p Pt.instance_variables

