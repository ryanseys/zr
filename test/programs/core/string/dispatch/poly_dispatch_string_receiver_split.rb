# A poly receiver whose method name a user class also owns.
#
# Any class can define `split` -- the bundled Pathname does. A genuine String
# must still take String#split, so `str.split.join(" ")` works. A receiver
# that matches no class raises, and does not give back a zero value.

class Path
  attr_reader :s

  def initialize(s)
    @s = s
  end

  def split
    [Path.new("a"), Path.new("b")]
  end

  def bytes
    [1, 2]
  end
end

module Util
  module_function

  def wrap(str) = str.split.join(" ")
  def widen(str) = str.length
end

# `help` comes off a rest-array pop, so the parameter is poly, not String
class Flag
  attr_reader :help

  def initialize(*opts)
    @help = opts.pop
  end
end

p Util.wrap("Usage:  slap   [options]")
p Util.wrap(Flag.new("-h", "some  help").help)
p Util.widen("abcd")

# the user's own method still wins for its own receiver
p Path.new("x").split.map { |q| q.s }

# a value that answers neither raises, rather than reading back as empty
def poly_split(v) = v.split
holder = [1, "a b"]
p poly_split(holder[1])
begin
  poly_split(holder[0])
  p "no raise"
rescue NoMethodError
  p "NoMethodError"
end
