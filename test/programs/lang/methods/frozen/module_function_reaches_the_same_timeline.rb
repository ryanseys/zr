# Ruby installs each `def` WHERE IT STANDS, so a call written between two
# same-name definitions answers the FIRST body. zr's static tables carry only
# the last-def-wins winner, so `analyze::redefs` puts the timeline in the
# runtime overlay instead: the first body installs at boot, and each later one
# re-installs at its own document position.
#
# The instance channel had that; the class-method channel did not -- `redefs`
# skipped `is_class_method` outright, so `C.t` answered the reopened body from
# the program's first line. The two channels are separate maps and separate
# hooks, which is what this file sweeps.
#
# No call-site change was needed: a class-method send is already dynamic (it
# has an explicit receiver), and the overlay outranks the frozen row. What was
# missing was the install.

puts "== module_function reaches it the same way"
module F
  module_function
  def g = "g1"
end
p F.g
module F
  module_function
  def g = "g2"
end
p F.g

