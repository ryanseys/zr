# `<expr>.singleton_class.prepend(M)` where the RECEIVER or the MODULE is not
# a compile-time constant. It runs as an ordinary send, and a later `X.m` call
# sees the override.
module Loud
  def greet = "LOUD " + super
end

module Softer
  def greet = "soft " + super
end

class Speaker
  def self.greet = "hi"
end

# The receiver reaches the class through a LOCAL -- not a constant path.
k = Speaker
k.singleton_class.prepend(Loud)
p Speaker.greet
p Speaker.singleton_class.ancestors.include?(Loud)

# The module reaches the call through an EXPRESSION -- also not a constant.
mods = [Softer]
Speaker.singleton_class.prepend(mods.first)
p Speaker.greet

# A method the modules do NOT define keeps answering the class's own.
def Speaker.name_tag = "speaker"
p Speaker.name_tag
