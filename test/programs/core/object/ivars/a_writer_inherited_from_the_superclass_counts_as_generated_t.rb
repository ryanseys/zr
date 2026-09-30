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

# A writer reached through the superclass counts as generated as well.
class Base
  attr_accessor :z
end
class Derived < Base
  def initialize
    @z = nil
  end
  def check
    if @z
      "inherited-set"
    else
      "inherited-unset"
    end
  end
end
dd = Derived.new
dd.z = "here"
puts dd.check

