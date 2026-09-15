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
k = Class.new { define_method(:m) { yield } rescue p $! }
begin; k.new.m { 1 }; rescue LocalJumpError => e; p e.message; end

__END__
#@ stderr
lang/blocks/a_break_leaves_the_define_method_call_it_was_given_to.rb: --> lang/blocks/a_break_leaves_the_define_method_call_it_was_given_to.rb

Invalid yield

>  4  p W.new([1, 2, 3]).take(2)
>  8  p via_each(W.new([4, 5]))
> 12  p V.new([1, 2, 3]).take(2)
> 16  p(U.new.each { |x| break x + 1 })
> 20  pr = T2.new.run { break 5 }
> 21  begin; pr.call; rescue LocalJumpError => e; p e.reason; end
> 22  k = Class.new { define_method(:m) { yield } rescue p $! }
> 23  begin; k.new.m { 1 }; rescue LocalJumpError => e; p e.message; end

lang/blocks/a_break_leaves_the_define_method_call_it_was_given_to.rb:22: syntax error found (SyntaxError)
  20 | pr = T2.new.run { break 5 }
  21 | begin; pr.call; rescue LocalJumpError => e; p e.reason; end
> 22 | ... yield } rescue p $! }
     |     ^~~~~ Invalid yield
  23 | begin; k.new.m { 1 }; rescue LocalJumpError => e; p e.message; end

#@ exit 1
