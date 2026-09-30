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

# Ruby lets a definition carry more than one trailing modifier, and the pair
# pushes into the class body exactly as a single one does. sexp_processor
# closes its whole `Sexp` reopen with two.
class Twice
  def base = :base
end

class Twice
  def added = :added
end unless Twice.new.respond_to? :added if ON

p Twice.new.added
p Twice.instance_methods(false).sort

class TwiceOff
  def base = :base
end

class TwiceOff
  def added = :added
end unless TwiceOff.new.respond_to? :added if OFF

p TwiceOff.new.respond_to?(:added)
p TwiceOff.instance_methods(false)
