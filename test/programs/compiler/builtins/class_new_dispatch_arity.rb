# Class-object `.new` dispatch (zero-arg) only builds classes whose initialize
# takes no required args; an arg-requiring constructor is omitted (as MRI
# raises ArgumentError for it), and a value-type class is built by value, not
# as a heap pointer.
class A
  def initialize; @v = "a"; end
  def v; @v; end
end
class Other
  def initialize(x); @x = x; end
  def x; @x; end
end
class Rel
  def initialize(model); @model = model; end
  def build; @model.new; end
end
puts Rel.new(A).build.v
puts Other.new("keep").x

# an optional-arg constructor is zero-arg-compatible: its arm fills the
# default
class WithOpt
  def initialize(attrs = {}); @attrs = attrs; end
  def size; @attrs.length; end
end
class WithOpt2
  def initialize(attrs = {}); @attrs = attrs; end
  def size; @attrs.length + 1; end
end
class Maker
  def initialize(model); @model = model; end
  def build; @model.new; end
end
puts Maker.new(WithOpt).build.size
puts Maker.new(WithOpt2).build.size
