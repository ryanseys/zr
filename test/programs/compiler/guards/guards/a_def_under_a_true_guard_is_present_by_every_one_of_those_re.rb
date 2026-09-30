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

# The guard is true, so it is there, by every one of those readings.
class Present
  if ON
    def only_when_on = :on
  end
end
p Present.new.only_when_on
p Present.new.respond_to?(:only_when_on)
p Present.instance_methods(false)

