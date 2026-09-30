

# A top-level `def` written in a box belongs to that box: main cannot call
# it.
#
# A top-level `def` is a private instance method of `Object`, and a box has
# its OWN `Object` -- so a `def` in a box means the `class Object` reopen
# that a box already isolates. The box does not make a SECOND class called
# `Object`.

b = Ruby::Box.new
b.eval("def leaked_helper = 1")
begin
  p leaked_helper
rescue NameError, NoMethodError => e
  p e.class
end
