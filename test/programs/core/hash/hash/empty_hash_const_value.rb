# An empty hash literal as a receiver ({}.freeze) gets the same type as a bare
# {}. The constant is defined, and a typed ivar's `|| CONST` fallback works.
class C
  EMPTY = {}.freeze
  def initialize
    @h = nil
  end
  def read
    @h || EMPTY
  end
end
p C.new.read
p C::EMPTY.empty?
p C::EMPTY.size
TOP = {}.freeze
p TOP
