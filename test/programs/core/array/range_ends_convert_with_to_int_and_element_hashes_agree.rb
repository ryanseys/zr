# slice! and values_at convert the ends of a Range with to_int. An
# element whose hash is an object hashes by that object's to_int, so it
# agrees with the Integer's own hash.
from = Object.new
to = Object.new
def from.<=>(_) = 0
def to.<=>(_) = 0
def from.to_int = 1
def to.to_int = -2
a = [1, 2, 3, 4, 5]
p a.slice!(from..to), a, [1, 2, 3, 4, 5].values_at(from..to)
h = Object.new
def h.to_int = 1.hash
ob = Object.new
ob.instance_variable_set(:@h, h)
def ob.hash = @h
p [ob].hash == [1].hash, 1.hash == [1][0].hash, { 1 => :a }[1], [1, 2, 1].uniq
