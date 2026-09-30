# `size` / `length` on a receiver of no single type answers an Integer --
# unless a user class owns the name and answers something else. Then the
# call can answer either the builtin Integer or the user method's value.
#
# A user `size` that answers an Integer agrees with the builtins, so the
# count stays a plain number.
class Widget
  def size(extra = nil) = [1, extra]
end
class Counter
  def size = 7
end
def mk(f) = f ? Widget.new : [1, 2]
def mk2(f) = f ? Counter.new : [1, 2]
p mk(true).size
p mk(false).size
p mk2(true).size
p mk2(false).size
p [Widget.new, [1,2]][0].size
p [Widget.new, [1,2]][1].size
p [Counter.new, "ab"][1].size
v = mk(true)
p v.size
p v.size.class
p({a: 1, b: 2}.size)
p [1,2,3].size
p "abc".size
p :sym.size
