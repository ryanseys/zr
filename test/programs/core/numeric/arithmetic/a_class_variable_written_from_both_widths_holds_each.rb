# A parameter can get a small Integer from one call and a Bignum from
# another. Each value must keep its own width, whatever way it reaches
# the parameter.

class Tally
  @@total = 0

  def self.bump(x)
    @@total = @@total + x
    @@total
  end
end
p Tally.bump(1)
p Tally.bump(2**80)

