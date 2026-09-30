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

c = Ctx.new
c.w = [0.5, 0.25]
puts probe(c)
# The same read reported the value as present all along, which is what made the
# bad branch silent rather than loud.
puts c.w.nil?
puts c.w.is_a?(Array)

