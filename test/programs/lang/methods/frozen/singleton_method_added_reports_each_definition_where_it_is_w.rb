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

puts "== singleton_method_added reports each definition where it stands"
class Hooked
  def self.singleton_method_added(n)
    (@seen ||= []) << n unless n == :singleton_method_added
    super
  end
  def self.a = "a1"
end
p Hooked.instance_variable_get(:@seen)
class Hooked
  def self.a = "a2"
end
p [Hooked.instance_variable_get(:@seen), Hooked.a]

