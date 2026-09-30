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

# A FALSE guard splices nothing.
module Chill
  def frosty? = true
end

$never = false
if $never
  class Thermos
    include Chill
  end
end
p Thermos.ancestors.include?(Chill)
begin
  Thermos.new.frosty?
rescue NoMethodError => e
  puts e.class
end

