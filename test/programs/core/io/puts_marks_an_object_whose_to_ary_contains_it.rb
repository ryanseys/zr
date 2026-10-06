# puts marks the object itself before its #to_ary runs, so an object
# whose items contain it prints "[...]" in its own place.
require "stringio"
c = Class.new do
  def to_ary = [self]
end
s = StringIO.new
s.puts(c.new)
p s.string

d = Class.new do
  def to_ary = [1, [self, 2]]
  def to_s = "d"
end
s = StringIO.new
s.puts(d.new)
p s.string

a = [1]
a << a
s = StringIO.new
s.puts(a, [a])
p s.string

# The same object twice, not inside itself, prints twice.
b = [[3], [3]]
s = StringIO.new
s.puts(b, b)
p s.string
$stdout.puts(c.new)
$stdout.puts([], [[]], nil)
