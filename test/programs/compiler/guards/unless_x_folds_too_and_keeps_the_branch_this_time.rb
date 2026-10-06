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

# `unless !x` -- the double negative folds too, and keeps the branch this time.
unless !defined?(StillNotHere)
  class NeverRuns
    def call
      "unreachable"
    end
  end
end

p defined?(NeverRuns).nil?

