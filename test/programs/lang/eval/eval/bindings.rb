# frozen_string_literal: true

# `binding` and `local_variables` read the CALLER's scope, so no method
# row can answer them: the compile writes them out of the cells the
# scope's names live in. A cell is the only storage a Binding can share,
# so a scope that takes one keeps every name in one.

def method_scope
  x = 1
  y = "two"
  b = binding
  [b.local_variables, b.local_variable_get(:x), b.receiver.class]
end
p method_scope
p local_variables

# The names come back the way ruby orders them: the innermost scope's
# own first, then the enclosing ones a block carries.
outer = 1
[9].each { |i| inner = 2; p local_variables }

# A binding writes back through the same cell the scope reads.
def written_back
  n = 1
  binding.local_variable_set(:n, 9)
  n
end
p written_back

# `Proc#binding` is the scope the proc was BUILT in: its own locals do
# not exist until it runs.
def make
  hidden = :in_make
  proc { hidden }
end
pr = make
p [pr.binding.local_variables, pr.binding.local_variable_get(:hidden)]

# A bare `eval` runs in the caller's binding, and so does one handed nil.
zz = 11
p [eval("zz + 1"), eval("zz + 2", nil), eval("zz + 3", binding)]

# `TOPLEVEL_BINDING` is `<main>`'s own frame.
p TOPLEVEL_BINDING.class
p TOPLEVEL_BINDING.source_location
p TOPLEVEL_BINDING.local_variable_get(:zz)

# A method's binding sees the receiver's instance variables and its cref.
class Holder
  LIMIT = 5
  def initialize = @v = 10
  def peek
    y = 1
    binding
  end
end
hb = Holder.new.peek
p [hb.eval("@v"), hb.eval("y"), hb.eval("LIMIT")]
