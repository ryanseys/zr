# frozen_string_literal: true

# `super` sends through the same three channels an ordinary call does:
# positionals with a `*` splat spread among them, a keyword Hash of its
# own, and the block. The Array the runtime reads is built here, so a
# splat is one different push and nothing else changes.

class Base
  def go(*args, **kw)
    ["base", args, kw]
  end

  def pair(a, b) = "#{a}/#{b}"
end

class Kid < Base
  def go(*args, **kw) = super(*args, **kw)
end

class Splatter < Base
  def go(head, *rest) = super(head, *rest, tail: rest.size)

  def pair(a, b) = super(*[a, b])
end

p Kid.new.go(1, 2, a: 3)
p Kid.new.go
p Splatter.new.go(1, 2, 3)
p Splatter.new.pair(:x, :y)

# A module's `super` walks the ancestors above the module, not above the
# class the method was called on.
module Loud
  def speak(word)
    "#{super(word)}!"
  end
end

class Quiet
  def speak(word) = word
end

class Shouter < Quiet
end
Shouter.include(Loud)

p Shouter.new.speak("hi")
p Shouter.ancestors.take(3).map(&:to_s)

# A body the runtime installed has no defining class until it runs, so
# the target comes off the method-frame stack instead.
P = Module.new do
  def label(*parts, sep: "-")
    "<#{super(*parts, sep: sep)}>"
  end

  def each_upper
    super { |v| yield v.upcase }
  end
end

class Plain
  def label(*parts, sep: "-") = parts.join(sep)

  def each_upper
    yield "a"
    yield "b"
  end
end
Plain.prepend(P)

p Plain.new.label("a", "b")
p Plain.new.label("a", "b", sep: "+")

seen = []
Plain.new.each_upper { |v| seen << v }
p seen

# A bare `super` still forwards the parameters by their CURRENT values.
class Renamer < Base
  def pair(a, b)
    a = "#{a}#{a}"
    super
  end
end
p Renamer.new.pair("q", "r")
__END__
["base", [1, 2], {a: 3}]
["base", [], {}]
["base", [1, 2, 3], {tail: 2}]
"x/y"
"hi!"
["Shouter", "Loud", "Quiet"]
"<a-b>"
"<a+b>"
["A", "B"]
"qq/r"
