# `obj.extend(Mod)` adds the module to the object's singleton class. The
# extended object runs the module's method and also answers `is_a?(Mod)`
# with true.
module Loud
  def speak = "LOUD"
end

module Soft
  def whisper = "soft"
end

class Base
  def speak = "base"
end

a = Base.new
a.extend(Loud)
p a.speak
p a.is_a?(Loud)
p a.is_a?(Base)
p a.is_a?(Soft)

# a sibling instance is untouched
p Base.new.is_a?(Loud)
p Base.new.speak

# two modules on one object
b = Base.new
b.extend(Loud)
b.extend(Soft)
p b.is_a?(Loud)
p b.is_a?(Soft)
p b.whisper

# and a plain include still answers the same way
class C
  include Loud
end

p C.new.is_a?(Loud)
p C.new.speak
