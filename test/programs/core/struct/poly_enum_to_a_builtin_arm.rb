# `obj.map { }` works when obj is an Array, also when a Struct in the program
# defines #each. Here a Struct member and an unrelated class's instance method
# share a name, so the parameter could be the Struct or an Array.
module Contract
  Pair = Struct.new(:registered)

  def self.spell(params)
    params.map { |x| x }
  end

  def self.pick(params)
    params.select { |x| true }
  end

  def self.walk
    [Pair.new].each do |pair|
      Contract.spell(pair.registered)
    end
  end

  class Builder
    def registered
      Pair.new
    end
  end
end

# an Array reaches the parameter the desugar typed as the Struct
p Contract.spell(Contract::Pair.new([1]).registered)
p Contract.spell([1, 2, 3])
p Contract.spell(["a", "b"])
p Contract.spell([1.5, 2.5])
p Contract.pick([1, 2])

# the Struct itself still goes through its own arm
p Contract.spell(Contract::Pair.new(9))

# and a Hash, which materializes as pairs
p Contract.spell({ a: 1 })
