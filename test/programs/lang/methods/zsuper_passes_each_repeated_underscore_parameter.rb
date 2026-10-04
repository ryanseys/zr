# A bare `super` passes each `_` parameter as it was given, though the
# name repeats.
class A
  def m(a, b) = [a, b]
  def m3(*a) = a
  def o(a, b = 2, *c) = [a, b, c]
end
class B < A
  def m(_, _) = super
  def m3(_, _, _) = super
  def o(_, _ = 9, *_) = super
end
p B.new.m(1, 2), B.new.m3(1, 2, 3), B.new.o(1), B.new.o(1, 5, 6, 7)
