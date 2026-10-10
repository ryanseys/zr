x = 1
y = 2
h = { x:, y: }
p h
p [1, 2, 3].map { it * 2 }, [1, 2].map { _1 + 1 }, [[1, 2]].map { _1 + _2 }
a, $g1, @i = 1, 2, 3
p a, $g1, @i
class U
  def gone = 1
  def stays = 2
  undef gone
  undef_method :stays rescue p $!.class
end
begin
  U.new.gone
rescue NoMethodError => e
  puts e.message
end
errs = [ArgumentError, TypeError]
begin
  raise TypeError, "t"
rescue *errs => e
  p e.class
end
smalls = [1, 2, 3]
case 2
when *smalls then p :small
end
begin
  raise "iv"
rescue => @err
end
p @err
def kw_yield = yield(1, k: 2)
kw_yield { |a, k:| p [a, k] }
def anon_rest(*) = other_rest(*)
def other_rest(*a) = a
p anon_rest(1, 2)
def anon_kw(**) = other_kw(**)
def other_kw(**k) = k
p anon_kw(a: 1)
def anon_blk(&) = other_blk(&)
def other_blk = yield
p anon_blk { :blk }
def fwd(...) = other_all(...)
def other_all(*a, **k, &b) = [a, k, b&.call]
p fwd(1, z: 2) { 3 }
