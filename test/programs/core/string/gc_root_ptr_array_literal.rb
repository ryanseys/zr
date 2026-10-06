# An `@x = [Klass.new(...)]` literal keeps the new array alive while each
# element is made. A GC during a later Klass.new does not free the
# half-built array.
#
# Each Tile holds a 256-float buffer (~2 KB), so a few hundred
# Containers cause GC runs in the middle of construction.

class Tile
  attr_accessor :tag, :data
  def initialize(tag)
    @tag  = tag
    @data = Array.new(256, tag.to_f)
  end
end

class Container
  attr_accessor :a, :b, :c
  def initialize
    @a = [Tile.new(10), Tile.new(20), Tile.new(30), Tile.new(40)]
    @b = [Tile.new(11), Tile.new(21), Tile.new(31), Tile.new(41)]
    @c = [Tile.new(12), Tile.new(22), Tile.new(32), Tile.new(42)]
  end
end

containers = [Container.new]
containers.pop

n = 0
while n < 1000
  containers.push(Container.new)
  n += 1
end

errors = 0
ci = 0
while ci < containers.length
  c = containers[ci]
  ta = c.a; tb = c.b; tc = c.c
  if ta.length != 4 || tb.length != 4 || tc.length != 4
    errors += 1
  else
    bad = false
    if ta[0].tag != 10 || ta[1].tag != 20 || ta[2].tag != 30 || ta[3].tag != 40
      bad = true
    end
    if tb[0].tag != 11 || tb[1].tag != 21 || tb[2].tag != 31 || tb[3].tag != 41
      bad = true
    end
    if tc[0].tag != 12 || tc[1].tag != 22 || tc[2].tag != 32 || tc[3].tag != 42
      bad = true
    end
    if bad
      errors += 1
    end
  end
  ci += 1
end

puts errors
