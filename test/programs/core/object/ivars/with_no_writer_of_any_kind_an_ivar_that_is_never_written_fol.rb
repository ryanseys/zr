# `if obj.attr` keeps its live branch when the backing ivar's only VISIBLE
# write is the constructor's nil and the real value arrives through a generated
# setter (attr_writer / attr_accessor), as in `c.w = [0.5]`. A branch folds
# away only when no writer of any kind can store a non-nil value.
class Ctx
  attr_accessor :w
  def initialize
    @w = nil
  end
end

def probe(c)
  if c.w
    "truthy"
  else
    "falsy"
  end
end

# The fold itself is still wanted: with no writer of any kind, an ivar written
# only nil really is statically falsy, and the branch really is dead.
class NoWriter
  attr_reader :m
  def initialize
    @m = nil
  end
end
nw = NoWriter.new
puts(nw.m ? "unreachable" : "correctly-falsy")
