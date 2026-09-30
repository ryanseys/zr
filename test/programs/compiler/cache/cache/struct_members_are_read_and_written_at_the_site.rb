# One reader site and one writer site over a Struct, a keyword
# Struct, a Data, an attr_accessor object and a subclass that
# redefines the reader: the cell's shape says which the site does
# in place, and every guard that fails takes the call.
Point = Struct.new(:x, :y)
Named = Struct.new(:x, :y, keyword_init: true)
Pair = Data.define(:x, :y)
class Reader
  attr_accessor :x, :y
  def initialize(x, y) = (@x = x; @y = y)
end
class Loud < Point
  def x = "loud #{super}"
end

def read_x(o) = o.x
def write_x(o, v) = o.x = v

things = [Point.new(1, 2), Named.new(x: 3, y: 4), Pair.new(x: 5, y: 6), Reader.new(7, 8), Loud.new(9, 10)]
p things.map { |t| read_x(t) }
p things.map { |t| read_x(t) }
writable = [things[0], things[1], things[3], things[4]]
p writable.map { |t| write_x(t, t.x.to_s * 2) }
p writable.map { |t| read_x(t) }

# A struct made with no values reads nil and takes a write.
bare = Point.allocate
p read_x(bare)
write_x(bare, :set)
p [read_x(bare), bare.y, bare.to_a]

# A frozen struct refuses the write at the site.
pt = Point.new(1, 2).freeze
begin
  write_x(pt, 3)
rescue => e
  p [e.class, e.message]
end
p read_x(pt)

# A member redefined after the site ran.
class Point; def x = "redefined"; end
p read_x(things[0])

# Ten thousand reads and writes through one site each.
acc = Point.new(0, 0)
10_000.times { |i| acc.y = acc.y + i }
p acc.y
p acc
