# The first pp requires ruby's pp.rb, as CRuby's prelude does, so a wide
# object wraps and a pretty_print method answers for its object.

p $LOADED_FEATURES.grep(/\/pp\.rb/).size
pp({aaaaaaaaaa: "bbbbbbbbbbbbbbbbbbbb", cccccccccccc: "dddddddddddddddddddd", eeeeeeeeeeee: [1,2,3,4,5,6,7,8,9]})
p $LOADED_FEATURES.grep(/\/pp\.rb/).size
S = Struct.new(:aaaaaaaaaaaaaaa, :bbbbbbbbbbbbbbbbbbbb, :ccccccccccccccccc)
pp S.new("x"*30, "y"*30, [1]*10)
class Point
  def initialize(x, y) = (@x, @y = x, y)
  def pretty_print(q) = q.text("P(#{@x}, #{@y})")
end
pp(Point.new(1, 2), 3)
p pp
x = pp [1]
p x
p Kernel.instance_method(:pp).owner
p method(:pp).arity
pp "x" * 100

__END__
0
{aaaaaaaaaa: "bbbbbbbbbbbbbbbbbbbb",
 cccccccccccc: "dddddddddddddddddddd",
 eeeeeeeeeeee: [1, 2, 3, 4, 5, 6, 7, 8, 9]}
1
#<struct S
 aaaaaaaaaaaaaaa="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
 bbbbbbbbbbbbbbbbbbbb="yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
 ccccccccccccccccc=[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]>
P(1, 2)
3
nil
[1]
[1]
Kernel
-1
"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
