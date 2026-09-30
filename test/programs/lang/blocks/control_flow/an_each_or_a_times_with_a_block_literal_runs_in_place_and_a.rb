# `ary.each { |x| }` and `n.times { |i| }` run in place at the site: the
# loop and the block's body in the caller's own function, with a frame
# for the builtin and one for the block linked under the caller's for
# the loop's duration. What a program sees is what the call gave it:
# the frames in a backtrace, `break`, `next`, `redo` and `return`, an
# exception rescued outside or inside, an ensure, the receiver mutated
# as it is walked, a block-local reset every turn, the answer, and a
# redefinition of the method, a subclass, or any other receiver, which
# take the call.
def frames = caller(0).map { |l| l[/in '(.*)'/, 1] }
def f
  [1].each { |x| p frames }
  2.times { |i| p frames if i == 1 }
  [1].each { |x| [2].each { |y| p frames } }
end
f
def g
  [1, 2, 3].each { |x| return x * 10 if x == 2 }
  :never
end
p g
r = []
[1, 2, 3, 4].each { |x| next if x.odd?; r << x }
p r
p [1, 2, 3].each { |x| break x + 100 if x == 2 }
p 5.times { |i| break i if i == 3 }
seen = 0
[1, 2].each { |x| seen += 1; redo if seen == 1 }
p seen
a = [1]
a.each { |x| a << x + 1 if a.size < 4 }
p a
b = [1, 2, 3, 4]
b.each { |x| b.pop }
p b
p [1, 2].each { |x; y| y = (y || 0) + x; p y }
begin
  [1, 2].each { |x| raise "in #{x}" if x == 2 }
rescue => e
  p [e.message, e.backtrace.map { |l| l[/in '(.*)'/, 1] }]
end
p frames
x = [1, 2].each { |v| begin; raise "no" if v == 1; rescue; p [:rescued, v]; ensure; p [:ensured, v]; end }
p x
p((1..3).to_a.each { |i| "a#{i}" =~ /a(\d)/ && p($1) })
def h = yield 5
p h { |v| [1].each { |x| p [v, x] }; 3.times { |i| next i } }
class MyArray < Array; def each = :mine; end
p MyArray.new([1]).each { |x| raise }
p({ a: 1 }.each { |k, v| p [k, v] })
p (2**70).times { break :big }
p [1, 2].each.next
p 3.times.to_a
t = 0
th = Thread.new { 200_000.times { |i| t += 1 } }
Thread.pass
th.join
p t
n = 0
100_000.times { |i| [1, 2].each { |x| n += x } }
p n
class Array; def each = :redefined; end
p [1].each { |x| raise }
class Integer; def times = :redefined; end
p 3.times { raise }
