# A module mixed into a subclass of a VALUE builtin, whose method calls
# `super`, must reach the builtin's own method correctly. The same
# `super` written directly in the subclass works (the second pair
# below), so this checks reaching the builtin THROUGH a module in the
# ancestry, not just the value-super channel itself. `DoubledArray`
# reaches `Array#size` where `DoubledPlain` reaches a user body.

module Doubled
  def size = super * 2
end

class DoubledArray < Array
  include Doubled
end

class Base
  def size = 5
end

class DoubledPlain < Base
  include Doubled
end

p DoubledArray.new(3).size
p DoubledPlain.new.size

# Written directly in the subclass, with no module in between, the same `super`
# is fine today.
class DirectArray < Array
  def size = super * 2
end

p DirectArray.new(3).size
