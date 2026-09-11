# A Hash, an Array or an object that holds itself ends its walk where
# CRuby does: the same two objects compared again inside their own
# comparison are equal, and an object inspected again inside its own
# inspect shows `...`.
h = {}
h[:a] = h
g = {}
g[:a] = g
p h == g, h.eql?(h), h.eql?(g), h == h.dup

a = []
a << a
b = []
b << b
p({a => 1}[b])
p a == b, a.eql?(b)

o = Object.new
o.instance_variable_set(:@a, o)
puts o.inspect.gsub(/0x\h+/, "0xXX")

s = Struct.new(:x)
v = s.new
v.x = v
puts v.inspect.gsub(/0x\h+/, "0xXX")
Point = Struct.new(:x)
w = Point.new
w.x = w
puts w.inspect
__END__
true
true
true
true
1
true
true
#<Object:0xXX @a=#<Object:0xXX ...>>
#<struct x=#<struct #<Class:0xXX>:...>>
#<struct Point x=#<struct Point:...>>
