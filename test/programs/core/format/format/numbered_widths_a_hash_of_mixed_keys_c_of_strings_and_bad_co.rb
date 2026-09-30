def t(*a) = p(format(*a))
t("%1$*2$d|%2$d", 5, 8)
t("%*d|%-*d|", -6, 3, 4, 2)
t("%{a} %<a>s", {"a" => 1, a: 2})
t("%c|%c|%5c|", "hello", 0x3042, "x")
p format("%c".encode("US-ASCII"), 200).encoding
o = Object.new
def o.to_ary = ["q", "r"]
p "%s %s" % o
h = Object.new
def h.to_hash = {k: 9}
p format("%{k}", h)
["%**d", "%.*.*d", "%1$d %d", "%d %1$d", "%<a>d %d"].each do |spec|
  format(spec, 1, 2, 3)
rescue ArgumentError => e
  p e.message
end
[-1, 0x110000].each do |c|
  format("%c", c)
rescue RangeError, ArgumentError => e
  p e.message
end
