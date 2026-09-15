class W < Array
  define_method(:each) { |*args, &blk| super(*args, &blk) }
end
p W.new([1, 2, 3]).take(2)
def via_each(o)
  o.each { |x| break x * 10 }
end
p via_each(W.new([4, 5]))
class V < Array
  def each(*args, &blk) = super(*args, &blk)
end
p V.new([1, 2, 3]).take(2)
class U < Array
  define_method(:each) { |&blk| [9].each { |x| blk.call(x) }; :fell_through }
end
p(U.new.each { |x| break x + 1 })
class T2
  define_method(:run) { |&b| b }
end
pr = T2.new.run { break 5 }
begin; pr.call; rescue LocalJumpError => e; p e.reason; end


__END__
[1, 2]
40
[1, 2]
10
:break
