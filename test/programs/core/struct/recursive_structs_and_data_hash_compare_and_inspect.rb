# Equal recursive structs hash the same, and a recursive comparison finds
# a difference anywhere. Data#with does not call new, and a recursive
# anonymous Data names its class in the marker.
Car = Struct.new(:make, :model, :year)
car = Car.new("H", "A", "1998")
similar = Car.new("H", "A", "1998")
car[:make] = car
similar[:make] = car
p car.hash == similar.hash
x = Car.new("H", "A", "1998")
x[:make] = x
st = Car.new("H", "A", "1998")
stone = Car.new(st, "A", "1998")
st[:make] = stone
p x == st, x.eql?(st)
stone[:year] = "1999"
p x == st, x.eql?(st)
a = [1]
a << a
b = [1]
b << b
p a.hash == b.hash, a.eql?(b)

M = Data.define(:amount, :unit)
sub = Class.new(M)
d = sub.new(amount: 42, unit: "km")
def sub.new(*) = raise("new called")
p d.with(unit: "m")
an = Class.new(M)
r = an.allocate
r.send(:initialize, amount: 42, unit: r)
p r.inspect.gsub(/0x\h+/, "XX")
