# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# PrettyPrint's own graph, reached through `pp`. See pp_pretty_print.rb.gccheck.

# At exit: cycle leak: 11 objects (Array x7, PP x1, PrettyPrint::Group x1, PrettyPrint::GroupQueue x1, Proc x1)
# Compiled code must not release a stack slot that holds no live value.
# Every local slot gets its first value on entry to the method, so no path
# (a normal exit or a raise) reaches a slot that has no value in it.
#
# Without `ZR_TEST_RT_LEAKCHECK=1` the program prints the right answer either
# way. The leak check finds a release of a bad slot.
#
# Oracle: the program prints its line and exits 0.
require "pp"

class Plain
end

PP.pp(Plain.new, +"")
puts "done"
