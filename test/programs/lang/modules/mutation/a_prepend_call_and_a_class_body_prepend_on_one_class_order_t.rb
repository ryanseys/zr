# Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
# (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
# that itself includes another), multiple separate prepend calls, interaction
# with a class-body `prepend` on the same class, and `super` from a prepended
# module reaching an INCLUDED module's method -- all resolved through the
# ordinary compile-time-flattened MRO, matching ruby.

# a prepend call interacting with a class-body prepend on the same class
module Early
  def val
    "E" + super
  end
end
module Late
  def val
    "L" + super
  end
end
class Mix
  prepend Early
  def val
    "mix"
  end
end
Mix.prepend(Late)
puts Mix.ancestors.first(4).inspect
puts Mix.new.val

