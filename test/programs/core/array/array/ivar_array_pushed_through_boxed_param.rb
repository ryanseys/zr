# `@rows = []` carries no element evidence, so it takes the empty-array
# default (an int array). A helper that pushes objects into it through a
# parameter shares that storage, and the ivar has to widen with it. Here the
# parameter arrives BOXED, so the call does not show which container the
# callee pushes into. The push must still store the objects.
Scenario = Struct.new(:key)

class Sheet
  def initialize
    @rows = []
  end

  def fill
    row(@rows, "a")
    row(@rows, "b")
    @rows
  end

  def row(rows, said)
    rows.push(Scenario.new(said))
  end

  def rows = @rows
end

s = Sheet.new
p s.fill.length
p s.rows.map { |r| r.key }
p s.rows.first.key

# A reader that hands the ivar out sees the widened array too.
p Sheet.new.fill.map { |r| r.key }

# An ivar that really does hold ints keeps its typed representation: the
# widening is driven by what the helper pushes, not by being passed at all.
class Counter
  def initialize
    @ns = []
  end

  def fill
    add(@ns, 1)
    add(@ns, 2)
    @ns
  end

  def add(ns, n)
    ns.push(n)
  end
end

p Counter.new.fill
p Counter.new.fill.sum
