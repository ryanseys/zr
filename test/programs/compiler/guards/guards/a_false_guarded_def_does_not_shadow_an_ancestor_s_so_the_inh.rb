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

# Nor does it shadow an ancestor's: with the guard false the inherited body
# answers, which takes the name not claiming a row on the subclass at all.
class Base
  def which = :base
end

class QuietSub < Base
  if OFF
    def which = :sub
  end
end
p QuietSub.new.which
p QuietSub.instance_methods(false)

class LoudSub < Base
  if ON
    def which = :sub
  end
end
p LoudSub.new.which

