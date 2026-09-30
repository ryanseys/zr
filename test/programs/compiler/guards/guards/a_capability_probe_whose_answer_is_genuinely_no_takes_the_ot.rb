# A class or module defined inside a top-level `if`.
#
# zr has to decide such a guard at compile time -- it registers definitions in
# one whole-program walk, so a definition it cannot prove reachable is a
# rejection rather than a runtime branch. `guard_fold` does the deciding, and
# two shapes it could not read cover most of the real gem guards.
#
#   !defined?(X)              a reload guard, and `static_bool` had no `!`
#   "".respond_to?(:m)        a capability probe on a LITERAL receiver, and
#                             `instance_class` mapped only `X.new` / bare `new`
#
# The gems: addressable writes the first; httpclient, em-websocket, highline and
# test-prof write the second.

# A capability probe whose answer is genuinely NO. String's surface is
# projected in full, so the absence is a fact rather than an unfinished class,
# and the branch is kept -- test-prof asks exactly this to detect ActiveSupport.
unless "".respond_to?(:parameterize)
  class Parameterizer
    def call
      "activesupport is not loaded"
    end
  end
end

p Parameterizer.new.call

