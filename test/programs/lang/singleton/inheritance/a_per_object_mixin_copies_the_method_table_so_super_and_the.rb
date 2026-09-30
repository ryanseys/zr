# `super` from a method mixed in through plain `obj.extend(M)`, or
# through the `class << obj; prepend M` spelling, must resume in the
# receiver class's own definition, and the mixed-in method must
# outrank the class's own method even for a statically-bound call
# site.

module Loud
  def speak
    "LOUD(" + super + ")"
  end
end

class Speaker
  def speak
    "plain"
  end
end

# (1) `super` from an extended module.
a = Speaker.new
a.extend(Loud)
p a.speak

# (2) the extended module outranking the class's own method.
b = Speaker.new
b.extend(Loud)
p b.speak

# The same two through the `class << obj` spelling.
c = Speaker.new
class << c
  prepend Loud
end
p c.speak

# An extend that ADDS a name (rather than overriding one) already works, and is
# what the corpus actually needs.
module Extra
  def extra
    "extra"
  end
end

d = Speaker.new
d.extend(Extra)
p [d.extra, d.speak, Speaker.new.respond_to?(:extra)]
