# `Module.used_modules` answered [] until the activation row could
# reach the callee. CRuby reads its cref's refinement table, which
# is keyed by the refined class, so the order is the classes in the
# order a `using` first reached them and, down each class, the
# newest refinement first -- Twice before Shout on String, and
# Twice before Plain on Integer, then uniq.
module Shout
  refine String do
    def loud = upcase
  end
end

module Twice
  refine String do
    def loud = upcase * 2
  end
  refine Integer do
    def loud = self * 2
  end
end

module Plain
  refine Integer do
    def loud = -self
  end
end

p Module.used_modules
p Module.used_refinements

using Shout
using Plain
using Twice

p Module.used_modules
p Module.used_refinements
p Module.used_refinements.map(&:target)

# A refinement holds its origin where no Ruby name reaches it.
p Module.used_refinements.first.instance_variables
p Module.used_refinements.first.to_s

# A method's body stands in the scope the `def` was written in, so
# it asks under the same rows.
def asks = Module.used_modules
p asks

p "hi".loud
