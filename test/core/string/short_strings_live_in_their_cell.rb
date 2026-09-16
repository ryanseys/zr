# A String of up to 87 bytes keeps them in its own cell; growing past
# that moves them to a buffer, and every way of writing keeps the
# bytes right across the move and back.
s = +"a" * 80
s << "b" * 20
puts s.size, s[78, 5]
s.replace("short")
puts s, s.size
s << "x" * 200
puts s.size, s[-3..]
s.replace("tiny")
puts s.dup, s.clone.frozen?, s.dup << "!"
t = s.dup
t[1, 2] = "ZZZZZZZZZZ" * 10
puts t.size, t[0, 4], s
u = +"seed"
100.times { |i| u.append_as_bytes(i.chr) }
puts u.bytesize, u.getbyte(4), u.getbyte(103)
v = String.new("abc", capacity: 500)
v << "d" * 90
puts v.size, v.encoding
w = "".dup
w.replace(w)
puts w.inspect
x = "abc".dup
x.replace(x)
x.insert(1, "Z" * 100)
puts x.size, x[0, 3], x[-2..]
y = ("k" * 50).freeze
puts y.frozen?, y.dup.size, (y + y).size, (y + y + y).size
z = 3.times.map { |i| "row #{i}" * 20 }
puts z.map(&:size).inspect, z[2][0, 5]
require "objspace"
puts ObjectSpace.memsize_of("x") <= ObjectSpace.memsize_of("x" * 1000)
puts ObjectSpace.memsize_of("x" * 1000) > 1000

__END__
100
aabbb
short
5
205
xxx
tiny
false
tiny!
102
tZZZ
tiny
104
0
99
93
UTF-8
""
103
aZZ
bc
true
50
100
150
[100, 100, 100]
row 2
true
true
