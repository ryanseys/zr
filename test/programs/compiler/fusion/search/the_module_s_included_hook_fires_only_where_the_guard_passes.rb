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

# The module's hook fires when (and only when) the guard passes, with the
# edited class as its argument.
module Tracked
  def self.included(base)
    $included_into = base.name
  end
end

class Ledger; end

$track = true
if $track
  class Ledger
    include Tracked
  end
end
p $included_into

