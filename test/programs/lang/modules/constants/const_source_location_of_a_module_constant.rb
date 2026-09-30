# `Module#const_source_location` answers where a constant was assigned,
# including a constant written in a module or class body, not just one
# set at run time.
#
# It is what a reloader or a diagnostic uses to say WHERE a duplicate
# constant came from -- the "already initialized constant" warning
# quotes it -- so this must stay precise.

module NS
  X = 1
  class Inner
    Y = 2
  end
end
Z = 3

p NS.const_source_location(:X)&.last
p NS::Inner.const_source_location(:Y)&.last
p Object.const_source_location(:Z)&.last
p NS.const_source_location(:Nope)
p Object.const_source_location(:NS)&.last

# A constant set at run time reports the caller's line.
NS.const_set(:W, 4)
p NS.const_source_location(:W)&.last
