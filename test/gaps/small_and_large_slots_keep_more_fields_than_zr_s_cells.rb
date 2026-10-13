# ruby's object slots (32 to 1024 bytes, in 12 sizes, 8 bytes a field)
# can keep more fields than zr's cells (64, 128 or 256 bytes, 16 bytes an
# entry). Where the slot is larger, ruby keeps the fields in it and zr
# moves them out. Plain objects keep 2 in ruby and 1 in zr.
require "objspace"

def embedded?(o) = ObjectSpace.dump(o).include?('"embedded":true')

o = Object.new
o.instance_variable_set(:@a, 1)
o.instance_variable_set(:@b, 2)
p embedded?(o)

[4, 12].each do |k|
  c = Class.new
  c.class_eval "def initialize; #{(0...k).map { |i| "@v#{i} = nil" }.join("; ")}; end", __FILE__, __LINE__
  o = c.new
  o.instance_variable_set(:@extra1, 1)
  o.instance_variable_set(:@extra2, 1)
  p [k, embedded?(o)]
end
