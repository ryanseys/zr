# Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
# (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
# that itself includes another), multiple separate prepend calls, interaction
# with a class-body `prepend` on the same class, and `super` from a prepended
# module reaching an INCLUDED module's method -- all resolved through the
# ordinary compile-time-flattened MRO, matching ruby.

# a prepended module that itself includes another (diamond expansion)
module Base
  def label
    "base"
  end
end
module Deco
  include Base
  def label
    "deco(" + super + ")"
  end
end
class Card
  def label
    "card"
  end
end
Card.prepend(Deco)
puts Card.ancestors.inspect
puts Card.new.label

