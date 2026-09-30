# Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
# (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
# that itself includes another), multiple separate prepend calls, interaction
# with a class-body `prepend` on the same class, and `super` from a prepended
# module reaching an INCLUDED module's method -- all resolved through the
# ordinary compile-time-flattened MRO, matching ruby.

# multiple SEPARATE prepend calls: the later one is closer
module P
  def tag
    "P" + super
  end
end
module Q
  def tag
    "Q" + super
  end
end
class Item
  def tag
    "item"
  end
end
Item.prepend(P)
Item.prepend(Q)
puts Item.ancestors.first(4).inspect
puts Item.new.tag

