# The def reads its arguments out of registers when the site hands
# it exactly its count (lib/zr/runtime/kernel/class.rb, MEntry.direct); every
# other road -- send, Method#call, an alias, a hook, a wrong count,
# keywords, super -- reads as before.
def one(a) = a
def two(a, b) = [a, b]
def four(a, b, c, d) = a + b + c + d
def blk(a, &b) = b.call(a)
def hash_arg(h) = h
p one(1), two(1, 2), four(1, 2, 3, 4), blk(5) { |x| x * 2 }
p hash_arg(k: 1), hash_arg({ k: 2 }), send(:one, 3), method(:two).call(4, 5)
alias uno one
p uno(7)
class Base; def go(x) = x + 1; end
class Kid < Base; def go(x) = super + 10; end
class Kid2 < Base; def go(x) = super(x) * 2; end
p Kid.new.go(1), Kid2.new.go(1)
class Hooked
  def self.method_added(name) = (@added ||= []) << name
  def a(x) = x
  def b(x, y) = y
  def self.added = @added
end
p Hooked.added, Hooked.new.a(1)
module M
  module_function
  def mf(x) = x * 3
end
p M.mf(2)
begin
  one
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first(2)
end
begin
  two(1, 2, 3)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first(2)
end
begin
  send(:four, 1)
rescue ArgumentError => e
  puts e.message
  puts e.backtrace.first(2)
end
def kw_plain(a) = a
p kw_plain(x: 1)
begin
  kw_plain(1, x: 2)
rescue ArgumentError => e
  puts e.message
end
o = Object.new
def o.sing(x) = x - 1
p o.sing(9)
p o.method(:sing).arity, method(:four).arity, method(:blk).parameters
class Sub < Base; end
p Sub.new.go(2)
class Base; def go(x) = x + 100; end
p Sub.new.go(2), Kid.new.go(1)
