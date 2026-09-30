# Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
# (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
# that itself includes another), multiple separate prepend calls, interaction
# with a class-body `prepend` on the same class, and `super` from a prepended
# module reaching an INCLUDED module's method -- all resolved through the
# ordinary compile-time-flattened MRO, matching ruby.

# reflection after a prepend call
module Track
  def step
    "T:" + super
  end
end
class Flow
  def step
    "flow"
  end
end
Flow.prepend(Track)
f = Flow.new
puts f.is_a?(Track)
puts f.kind_of?(Flow)
puts Flow.ancestors.inspect
puts Flow.include?(Track)
puts f.step

