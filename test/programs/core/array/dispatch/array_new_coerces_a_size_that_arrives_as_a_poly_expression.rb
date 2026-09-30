# Array.new(size, fill) where the type of `size` is not known before run time.
#
# Mat#initialize's `ncols` gets an Integer from `Mat.new(2, 3)` and an untyped
# ivar from `Mat.new(1, @d)`. The size `nrows * ncols` must still work as an
# Integer.
class Mat
  def initialize(nrows, ncols)
    @flat = Array.new(nrows * ncols, 0.0)
  end
  def len
    @flat.length
  end
end

# No code calls this method, but its call site passes an untyped ivar @d as
# Mat#initialize's ncols. With Mat.new(2, 3) below, ncols gets two types of
# argument.
class Other
  def go
    Mat.new(1, @d)
  end
end

m = Mat.new(2, 3)
puts m.len
