# ruby 4.1 gives a class's objects the smallest slot that holds the
# instance variables that its initialize writes, so the slot keeps
# exactly that many (or the few more the slot rounds up to). A program's
# next ivar moves the fields out, memsize_of counts only the slot, and a
# removal that leaves few enough moves them back.
require "objspace"

def embedded?(o) = ObjectSpace.dump(o).include?('"embedded":true')

def expecting(k)
  Class.new do
    define_method(:fill) { |n| n.times { |i| instance_variable_set(:"@v#{i}", i) } }
    class_eval "def initialize; #{(0...k).map { |i| "@v#{i} = nil" }.join("; ")}; end", __FILE__, __LINE__
  end
end

[2, 3, 6, 7, 8, 9, 10].each do |k|
  c = expecting(k)
  kept = (k..k + 4).find { |n| o = c.new; o.fill(n); !embedded?(o) }
  o = c.new
  size = ObjectSpace.memsize_of(o)
  o.fill(kept)
  puts "expects #{k}: moves out at #{kept}, memsize #{ObjectSpace.memsize_of(o) == size ? "same" : "grew"}"
  o.remove_instance_variable(:"@v#{kept - 1}")
  p [embedded?(o), o.instance_variables.size]
end

# A subclass's initialize adds to what its superclass's objects get.
base = expecting(3)
sub = Class.new(base) do
  def initialize
    super
    @w = 1
    @x = 2
    @y = 3
  end
end
s = sub.new
p embedded?(s), s.instance_variables.size
s.instance_variable_set(:@z, 4)
p embedded?(s)

# An ivar written in a block of initialize does not count.
c = Class.new do
  def initialize
    @a = @b = @c = @d = @e = @f = 1
    [1].each { @g = 2 }
  end
end
p embedded?(c.new), c.new.instance_variables.size

# Object.new stays small after a plain object grows.
plain = Object.new
before = ObjectSpace.memsize_of(Object.new)
20.times { |i| plain.instance_variable_set(:"@p#{i}", i) }
p ObjectSpace.memsize_of(plain) == before, ObjectSpace.memsize_of(Object.new) == before, embedded?(plain)
