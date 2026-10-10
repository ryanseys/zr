class Foo
  def old = :old
  alias new1 old
  alias_method :new2, :old
  def raiser = raise("x")
  alias raiser2 raiser
end
p Foo.new.new1, Foo.new.new2
begin
  Foo.new.raiser2
rescue => e
  puts e.backtrace.first
end
def classify(x)
  case x
  when 1, 2 then :small
  when Integer then :int
  when "a", :b then :ab
  when String then :str
  when nil then :nil
  else :other
  end
end
p classify(1), classify(9), classify("a"), classify(:b), classify("z"), classify(nil), classify([])
v = case
    when false then 1
    when 1 > 0 then 2
    end
p v
p(case 5 when 6 then :no end)
class Counter
  @@count = 0
  @@names = []
  def self.count = @@count
  def initialize(name)
    @@count += 1
    @@names << name
    @@last ||= name
  end
  def names = @@names
  def last = @@last
end
Counter.new(:a)
Counter.new(:b)
p Counter.count, Counter.new(:c).names, Counter.new(:d).last
class Sub < Counter
  def sub_count = @@count
end
p Sub.new(:e).sub_count
class NoCvar
  def x = @@nope
end
begin
  NoCvar.new.x
rescue NameError => e
  puts e.message
end
$g = 1
$g += 2
p $g, $unset
def glob = $g * 10
p glob
h = { a: 1 }
h[:a] += 5
h[:b] ||= 7
h[:a] &&= 0
p h
arr = [1, 2]
arr[0] *= 10
p arr
class Box
  attr_accessor :v
end
b = Box.new
b.v = 1
b.v += 1
b.v ||= 9
p b.v
n = nil
p n&.length, "abc"&.length, n&.foo(1, 2)
X ||= 5
X ||= 6
p X
class WithLocals
  base = 10
  SIZE = base * 2
end
p WithLocals::SIZE
for i in [1, 2, 3]
  last = i
end
p i, last
for a, b in [[1, 2], [3, 4]]
  p [a, b]
end
r = for q in [1, 2] do break q * 100 if q == 2 end
p r
p((for z in [] do end))
