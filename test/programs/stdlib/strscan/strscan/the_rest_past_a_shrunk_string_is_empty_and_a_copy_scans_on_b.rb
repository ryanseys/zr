# The rest past a string that shrank is empty; scan_integer needs an
# ASCII-compatible string; a copy scans on by itself; there is no clear.
require "strscan"
x = +"abcdef"
s = StringScanner.new(x)
s.pos = 6
x.replace("ab")
p [s.rest, s.rest_size, s.eos?]
p((StringScanner.new("1".encode("UTF-16LE")).scan_integer rescue $!))
s = StringScanner.new("abc")
s.scan(/a/)
d = s.dup
d.scan(/b/)
p [s.pos, d.pos, d.matched, s.matched]
p((StringScanner.new("a").clear rescue $!), StringScanner.private_instance_methods(false).sort)
