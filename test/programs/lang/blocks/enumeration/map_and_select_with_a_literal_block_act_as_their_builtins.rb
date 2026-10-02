# Array#map and Array#select with a block literal run as a loop at the
# site (Function::Iterators). They must give what the builtins give:
# `next` gives the element's value and `break` the call's value; select
# pushes the element that is at the index after the block ran (nil if
# the block shortened the Array); an Array that grows during the loop
# is read to its new end; `return` leaves the method; a raise shows the
# builtin's frame; and a redefinition of Array#map is called.
a = [1, 2, 3, 4, 5]
p a.map { |x| x * 2 }
p a.select { |x| x.odd? }
p a.map { |x| next 0 if x == 3; x }
p a.select { |x| next true if x > 3; false }
p a.map { |x| break :stop if x == 4; x }
p a.select { |x| x = 99; x > 50 }
b = [1, 2, 3]
p b.map { |x| b << x if b.size < 6; x }
c = [1, 2, 3, 4]
p c.select { |x| c.clear if x == 2; true }
p [].map { |x| x }
p a.map { }
p a.map { |x| [x].map { |y| y + 1 } }
p({ a: 1 }.map { |k, v| [k, v] })
p((1..3).map { |x| x * 3 })
def first_big(xs) = xs.map { |x| return x if x > 2; x }
p first_big(a)
begin
  a.map { |x| raise "boom" if x == 2 }
rescue => e
  puts e.backtrace.first(3).map { |l| l.sub(/^.*?:/, "") }
end
i = 0
r = a.map { |x| i += x; i }
p r, i
class Array
  def map = :redefined
end
p a.map { |x| x }
p a.select { |x| x > 4 }
