# String#freeze gives back the room a frozen String cannot use, as
# rb_str_resize does: short bytes move into the cell, and a long buffer
# loses its spare room. A read into a buffer gives it room for the
# length asked (io_setstrbuf), and String.new reserves its capacity
# (test_optimization.rb, test_string_freeze_saves_memory).
require "objspace"
n = 16384
data = '.'.freeze
r, w = IO.pipe
w.write data
s = r.readpartial(n, '')
p ObjectSpace.memsize_of(s) >= n
s.freeze
p ObjectSpace.memsize_of(data) == ObjectSpace.memsize_of(s)
p s
big = "x" * 5000
big << "y"
p ObjectSpace.memsize_of(big) > 5002 + 1024
big.freeze
p ObjectSpace.memsize_of(big) < ObjectSpace.memsize_of("x" * 5001) + 1100
p big.size, big[-1]
c = String.new(capacity: 4000)
p ObjectSpace.memsize_of(c) >= 4000
c << "abc"
p c, c.encoding
d = String.new("hi", capacity: 1000)
p ObjectSpace.memsize_of(d) >= 1000, d
r.close; w.close
