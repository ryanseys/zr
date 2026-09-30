# A `Method` or `UnboundMethod` names ONE entry in the chain, also under
# `prepend`:
#
#   * `super_method` advances past the prepended module, so the idiomatic
#     `while m; m = m.super_method; end` walk reaches `Sub`, then `Base`, and
#     stops.
#   * `Base.instance_method(:greet).bind(sub)` runs `Base`'s body alone and
#     answers "base". It does not dispatch again from the top of the chain.
#
# `bind` is important: an UnboundMethod taken from a named ancestor is how
# you bypass an override on purpose (`Base.instance_method(:x).bind_call`
# is the standard way to defeat a `method_missing` proxy or a prepended
# wrapper).

class Base
  def greet = "base"
end
module Mixin
  def greet = "mixin+" + super
end
class Sub < Base
  prepend Mixin
  def greet = "sub+" + super
end

m = Sub.new.method(:greet)
p m.owner
p m.super_method.owner
p m.super_method.super_method.owner
p m.call

p Base.instance_method(:greet).bind(Sub.new).call
p Base.instance_method(:greet).bind_call(Sub.new)
p Sub.instance_method(:greet).owner
p Mixin.instance_method(:greet).owner

# The chain walk, with a limit so that the loop always ends.
walk = []
cur = Sub.new.method(:greet)
20.times do
  break unless cur
  walk << cur.owner.to_s
  cur = cur.super_method
end
p walk
