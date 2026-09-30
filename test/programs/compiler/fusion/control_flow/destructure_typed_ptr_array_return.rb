# A top-level `y, z = call_returning_pair_of_objs` with no constant
# target. The call must run in its place in the program, after the
# assignments to the locals that it reads.

class Mat
  attr_accessor :nrows, :ncols
  def initialize(nrows, ncols)
    @nrows = nrows
    @ncols = ncols
  end
  def matmul(other)
    Mat.new(@nrows, other.ncols)
  end
end

def fwd(w, x)
  y = w.matmul(x)
  z = w.matmul(x)
  [y, z]
end

w = Mat.new(3, 4)
x = Mat.new(4, 1)
y, z = fwd(w, x)
puts y.nrows
puts z.ncols
