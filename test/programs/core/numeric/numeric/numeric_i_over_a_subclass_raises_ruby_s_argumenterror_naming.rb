# `Numeric#i` builds `Complex(0, self)`. Here `self` is a Deg, a user
# subclass of `Numeric`.
#
# Complex holds a user `Numeric` subclass and dispatches every component
# operation to it. `p n.i` calls `Complex#inspect`, which asks whether the
# imaginary part is negative. That calls `Comparable#<` on the Deg, and the
# compare of a Deg with 0 fails.
#
# So the program raises ruby's ArgumentError from ruby's line with ruby's
# message. The trace names the frames under it: `Comparable#<`,
# `Complex#inspect` and `Kernel#p`, then `<main>`.
#
# Deg defines `to_f` and `inspect`, but not `<=>`, so the compare has no
# answer. The `rescue TypeError` does not catch the ArgumentError, and the
# program exits with status 1. (This comment keeps `p n.i` on line 27.)
#

class Deg < Numeric
  def initialize(v) = @v = v
  def to_f = @v.to_f
  def inspect = "Deg"
end

n = Deg.new(7)

begin
  p n.i
rescue TypeError => e
  puts "i: #{e.message}"
end
