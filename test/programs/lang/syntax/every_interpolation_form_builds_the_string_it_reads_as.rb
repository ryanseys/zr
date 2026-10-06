# Expression shapes: multi-value return/break/next, parenthesized
# statement sequences, the fuller interpolation forms, and top-level
# instance variables.

# --- string interpolation forms ---------------------------------------------
# Several statements inside #{ } answer the last...
p "v=#{1; 2}"
p "v=#{x = 3; x * 2}"
p x                       # ...and, like parens, leak their locals

# An empty #{} interpolates nothing.
p "a#{}b"

# Brace-less #@ivar / #$global interpolation.
$greeting = "hi"

class Speaker
  def initialize
    @name = "sam"
  end

  def to_s
    "#$greeting, #@name"
  end
end
puts Speaker.new

