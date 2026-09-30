# A closure can capture a local that holds a class, also when the block is a
# real closure and not an inlined loop. Locals can have the names of C
# keywords (`struct`, `int`, `default`).
rings = ""
rings = [[1, 2], [3, 4]]

struct = Struct.new :x, :y
int = 5
default = "d"

# the reported shape: the block never runs here, but it still has to compile
empty = ""
empty = []
empty.each do |ring|
  ring.sum do |lon, lat|
    struct.new lon, lat
  end
end

p rings.map { |r| struct.new(r[0], r[1]).x + int }
p rings.map { |_r| default }
p rings.map { |r| struct.new(r[0], r[1]).to_a }

mk = struct
p mk.new(9, 8).y

k = String
p rings.map { |_r| k }.first
puts "OK"
