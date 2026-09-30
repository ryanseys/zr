# `!` is an ordinary overridable method in ruby (`BasicObject#!`), and a class
# that defines it decides its own truthiness under `!`. So `!x` calls the
# override.
#
# `not x` is the same send and also calls it. A plain truthiness test
# (`x ? a : b`) correctly does NOT call it, so the override changes only the
# explicit operator -- which is why ruby made `!` a real method in 1.9. Null
# object and Maybe-shaped wrappers use this.

class Inverted
  def !() = :bang_called
end

i = Inverted.new
p !i
p (not i)
p !!i

class Blank
  def !() = true
end
b = Blank.new
p !b
p b ? :truthy : :falsy
