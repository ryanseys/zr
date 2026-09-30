# A `def` inside a class-body `if` whose guard zr cannot decide runs only if
# the guard says so -- which means it must claim no compile-time method-table
# row, because that row would answer whether or not the branch ran. What the
# guard installs goes into the runtime overlay instead, and the overlay is what
# answers: it already outranks a class's own table and an inherited one both.
#
# The name still has to REGISTER, so the compile-time machinery that resolves
# `extend` and the method tables can see it. Registering it is not the same as
# promising it.

OFF = ENV.fetch("ZR_TEST_CONDITIONAL_DEF_UNSET", "off") == "on"
ON = ENV.fetch("ZR_TEST_CONDITIONAL_DEF_UNSET", "off") == "off"

# The top-level `class X ... end if cond` form reopens through the same
# machinery (`analyze::try_conditional_reopen` pushes the guard into the class
# body), so it decides the same way. pp.rb's `class Set ... end if set_pp` is
# the shape.
class Reopened
  def base = :base
end

class Reopened
  def added = :added
end if OFF

p Reopened.new.respond_to?(:added)
p Reopened.instance_methods(false)

