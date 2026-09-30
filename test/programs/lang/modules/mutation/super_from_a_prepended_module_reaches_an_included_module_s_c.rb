# Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
# (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
# that itself includes another), multiple separate prepend calls, interaction
# with a class-body `prepend` on the same class, and `super` from a prepended
# module reaching an INCLUDED module's method -- all resolved through the
# ordinary compile-time-flattened MRO, matching ruby.

# super from a prepended module reaching an INCLUDED module's method
module Common
  def go
    "common"
  end
end
class Runner
  include Common
end
module Hook
  def go
    "hook(" + super + ")"
  end
end
Runner.prepend(Hook)
puts Runner.new.go
puts Runner.ancestors.inspect
