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

# hammertime's exact shape: Object itself, behind its own idempotence probe.
module Hammer
  def hammer_time? = true
end

unless ::Object < Hammer
  class ::Object
    include ::Hammer
  end
end
p 42.hammer_time?
p "anything".hammer_time?
puts "still running"
