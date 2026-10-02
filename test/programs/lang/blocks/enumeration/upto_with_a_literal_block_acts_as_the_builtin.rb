# Integer#upto with a block literal runs as a loop at the site when both
# ends are fixnums (Function::Iterators). It must give what the builtin
# gives: the receiver at the end, `break` and `next` as in a block, no
# iteration when the limit is below the receiver, the call for a Float
# or Bignum limit or without a block, `return` from the method, the
# builtin's frame in a backtrace, and a redefinition of Integer#upto.
s = 0
1.upto(5) { |i| s += i }
p s
p 3.upto(1) { |i| p i }
p 1.upto(4) { |i| break i * 10 if i == 3 }
p 1.upto(4) { |i| next if i.odd?; p i }
r = []
-2.upto(2) { |i| r << i }
p r
p 1.upto(3.5) { |i| p i }
p 1.upto(2**64) { |i| break i if i > 2 }
p 1.upto(3).to_a
def f(n) = 1.upto(n) { |i| return i if i * i > n }
p f(20)
begin
  1.upto(3) { |i| raise "x" if i == 2 }
rescue => e
  puts e.backtrace.first(3).map { |l| l.sub(/^.*?:/, "") }
end
class Integer
  def upto(n) = :mine
end
p 1.upto(3) { |i| i }
