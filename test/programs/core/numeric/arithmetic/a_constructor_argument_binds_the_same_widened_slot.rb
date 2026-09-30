# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

# a constructor argument is the same binding
class Box
  def initialize(v)
    @v = v.to_s
  end

  def show
    @v
  end
end
p Box.new(9).show
p Box.new(2**90).show

