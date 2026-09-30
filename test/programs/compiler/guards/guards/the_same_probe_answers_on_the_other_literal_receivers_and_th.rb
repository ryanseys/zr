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

# The same probe on the other literal receivers, and through a method the
# receiver inherits (`tap` comes from Kernel, not Array).
unless [].respond_to?(:sum)
  class Array
    def sum
      -1
    end
  end
end

unless({}.respond_to?(:tap))
  class Hash
    def tap
      -1
    end
  end
end

unless 1.respond_to?(:zero?)
  class Integer
    def zero?
      false
    end
  end
end

p [1, 2, 3].sum
p({ a: 1 }.tap { |h| h[:b] = 2 })
p 0.zero?

