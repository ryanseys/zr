# The CLASS-METHOD channel swept against ruby: every way a module can be
# seated in a singleton class, every order they can be written in, and what
# `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
# reflection surface answer at each position.
#
# zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
# instance ancestry: per non-module ancestor, its singleton prepends, its own
# `def self.x` layer, then its extends. A class method resolves down that
# derived chain exactly as an instance method resolves down an ordinary one --
# which is why this file asks the same questions of both sides wherever it
# can.
#
# The shapes that made it worth sweeping: a module reached BOTH ways holds two
# positions and runs once per position; a materialized copy of an extended
# module's method bakes the class it was extended ONTO while sitting at the
# MODULE's position; and a `super` resolved at compile time enters a body the
# walk also knows a position for, so it has to publish the same one.

module M1
  def tag = "M1(#{defined?(super) ? super : :top})"
end
class One
  extend M1
end

puts "== an own def self.x sits BEFORE the extended module"
class OwnFirst
  extend M1
  def self.tag = "own(#{defined?(super) ? super : :top})"
end
p OwnFirst.tag
p OwnFirst.method(:tag).owner.to_s
p OwnFirst.method(:tag).super_method&.owner.to_s

