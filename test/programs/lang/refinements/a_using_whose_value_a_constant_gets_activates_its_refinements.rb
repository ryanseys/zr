# `X = using mod` activates the refinements, as a `using` statement does,
# and the constant gets using's value: self (rbs's Module tests write
# `UsingReturnValue = using Module.new` in a module body).
module Shout
  refine(String) { def shout = upcase + "!" }
end

module Loud
  before = ("a".shout rescue :no_method)
  Returned = using Shout
  p before, "hi".shout, Returned.equal?(self), Returned
end

TopReturned = using Shout
p TopReturned.equal?(self), TopReturned.inspect, "top".shout

class Holder
  Inner = using Module.new
  p Inner.equal?(Holder)
end
