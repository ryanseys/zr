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

# A hand-written setter is the boundary on the other side: its body holds a
# real write node, which the scan counts, so the branch stays live.
class HandWritten
  attr_reader :h
  def initialize
    @h = nil
  end
  def h=(v)
    @h = v
  end
end
hw = HandWritten.new
hw.h = [2.0]
puts(hw.h ? "hand-written-set" : "hand-written-unset")

