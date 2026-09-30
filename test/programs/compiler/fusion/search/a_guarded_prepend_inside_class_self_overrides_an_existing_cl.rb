# A mixin into an EXISTING class under a runtime-undecidable guard is a
# runtime ancestry edit: the directive runs as the send it is, exactly when
# the guard passes (hammertime's `unless ::Object < Hammertime` idempotence
# guard, clusterer's `$LINALG == true`). Call sites the module could newly
# answer or override are de-optimized, so a folded call cannot bypass the
# splice -- and before the guard runs, the ancestry is untouched.
module Warmth
  def warmed? = true
end

class Thermos
  def temperature = 20
end

# The singleton half (`class << self; prepend M`), overriding an existing
# class method.
module Announcing
  def open = "announcing: " + super
end

class Shop
  def self.open = "9am"
end

$noisy = true
if $noisy
  class Shop
    class << self
      prepend Announcing
    end
  end
end
p Shop.open

