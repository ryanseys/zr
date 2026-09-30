# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

# a conditional whose arms are an int and a Bignum
class Either
  def initialize(f)
    @v = f ? 0 : 2**90
  end

  def show = @v.to_s
end
p Either.new(true).show
p Either.new(false).show
