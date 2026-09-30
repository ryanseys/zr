# Inside a class body, a call with a receiver takes its type from
# the receiver's method, not from the enclosing class.
#
# Here an open-class method on Integer returns a Hash. `C#wrap`
# calls `x.to_pair`, and the enclosing class C has no `to_pair`.
# The call still answers the Hash.

class Integer
  def to_pair
    {a: self, b: self * 2, c: self * 3}
  end
end

class C
  def wrap(x)
    x.to_pair
  end
end

h = C.new.wrap(5)
puts h[:a]   # 5
puts h[:b]   # 10
puts h[:c]   # 15
