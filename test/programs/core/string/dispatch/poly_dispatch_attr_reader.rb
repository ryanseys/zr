# An attr_reader-defined accessor on a polymorphic receiver works the
# same as an explicit `def v; @v; end`.

class C
  def initialize(v); @v = v; end
  attr_reader :v
end

class D
  def initialize(v); @v = v; end
  attr_reader :v
end

# Same return type per class (string) — result temp stays
# `const char *`, no boxing.
def make(flag)
  flag ? C.new("c-val") : D.new("d-val")
end

puts make(true).v
puts make(false).v

# Mixing an explicit `def v` on one class with attr_reader on
# others. The dispatcher must cover both shapes.
class F
  def initialize(v); @v = v; end
  def v; @v; end
end

def mix(flag)
  flag ? C.new("from-attr") : F.new("from-def")
end

puts mix(true).v
puts mix(false).v
