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

# The other entry point: a generated writer plus a direct @w read inside the
# class, which reaches the fold through static_nil_ivar_cond instead.
class Direct
  attr_writer :v
  def initialize
    @v = nil
  end
  def check
    if @v
      "set"
    else
      "unset"
    end
  end
end

d = Direct.new
d.v = 7
puts d.check

