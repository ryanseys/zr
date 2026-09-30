# The named calls with a fast path: what they answer on the road, past
# the fixnums, on a frozen receiver, and once the method is redefined.
s = "abc".b
p s.getbyte(1), s.getbyte(-1), s.getbyte(3)
begin
  s.getbyte(2**70)
rescue RangeError => e
  p e.class
end
s.setbyte(0, 0x41)
s.setbyte(-1, 256 + 0x5A)
p s
begin
  s.setbyte(3, 1)
rescue IndexError => e
  p e.message
end
begin
  "x".freeze.setbyte(0, 1)
rescue FrozenError => e
  p e.class
end
p 41.succ, -1.succ, (2**62 - 1).succ, (2**62 - 1).succ.class, (2**70).succ
begin
  1.5.succ
rescue NoMethodError => e
  p e.class
end
a = [1, 2]
p a.push(3), a.pop, a.shift, a, a.empty?, [].empty?
begin
  [1].freeze.push(2)
rescue FrozenError => e
  p e.class
end
class Array
  def push(x) = "no push of #{x}"
  def empty? = :never
end
class String
  def getbyte(i) = :byte
end
class Integer
  def succ = self + 10
end
p [1].push(2), [].empty?, "a".getbyte(0), 5.succ, "a".setbyte(0, 98), [3].pop, [4, 5].shift
