# A `using` at the toplevel of a string that an eval runs in a Binding
# stays in that Binding: the next eval in the same Binding sees the
# refinement. Another Binding, and an eval with no Binding, do not.
module Backwards
  refine String do
    def upcase = reverse
  end
end

module First; B = binding; end
module Second; B = binding; end

b = First::B
p eval(%{"before".upcase}, b)
p eval(%{using Backwards; "during".upcase}, b)
p eval(%{"after".upcase}, b)
p b.eval(%{"by Binding#eval".upcase})
p b.local_variable_defined?(:x)

c = Second::B
p c.eval(%{"other binding".upcase})
p c.eval(%{using Backwards; x = "via Binding#eval".upcase; x})
p eval(%{"then Kernel#eval".upcase}, c)
p c.local_variable_get(:x)
p "toplevel".upcase
