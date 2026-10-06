# `raise ... unless x.is_a?(C)` (and the equivalent
# `if !x.is_a?(C); raise ...; end` shape) is a definite-throw
# type assertion: when control reaches the statement after the
# guard, `x` is provably of class `C`. For example:
#
#   def process(x)
#     raise TypeError, "expected A" unless x.is_a?(A)
#     puts x.body
#   end
#
# After the guard, `x.body` is A#body, which answers a String, and
# not B#body, which answers an Integer. The narrow holds for the rest
# of the method body.

class A
  attr_accessor :body
  def initialize; @body = "from-A"; end
end

class B
  attr_accessor :body
  def initialize; @body = 42; end
end

def pick(n)
  n > 0 ? A.new : B.new
end

def process_unless(x)
  raise "expected A" unless x.is_a?(A)
  puts x.body
end

def process_if_negated(x)
  if !x.is_a?(A)
    raise "expected A"
  end
  puts x.body
end

# Both spellings should resolve identically -- a single call to
# A#body.
process_unless(pick(1))
process_if_negated(pick(1))

# Multiple guards in sequence accumulate narrows.
class S
  attr_accessor :name
  def initialize; @name = "sized"; end
end

def render(s, t)
  raise "expected S" unless s.is_a?(S)
  raise "expected S" unless t.is_a?(S)
  puts s.name + "/" + t.name
end

render(S.new, S.new)
