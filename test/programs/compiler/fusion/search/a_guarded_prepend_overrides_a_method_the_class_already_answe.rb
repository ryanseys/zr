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

# A prepend that OVERRIDES a method the class already answers -- the
# de-optimization is what keeps a statically-resolved `capacity` from
# reaching the class's own body underneath the override.
module Doubled
  def capacity = super * 2
end

class Bottle
  def capacity = 350
end

unless Bottle < Doubled
  class Bottle
    prepend Doubled
  end
end
p Bottle.new.capacity
p Bottle.ancestors.first == Doubled

