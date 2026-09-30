# A receiverless call resolves against the enclosing definition's self. A
# top-level `def` is a private method on Object, so it sits at the BOTTOM of
# every ancestry -- last, not first.
#
# So the call goes to the method on self, and that method gets the
# caller's array.
#
# The top-level methods below are never called and never passed anywhere.
Scenario = Struct.new(:key)

module Blocks
  def self.run
    scenarios = []
    heading(scenarios, "a")
    heading(scenarios, "b")
    scenarios
  end

  def self.heading(scenarios, said)
    scenarios.push(Scenario.new(said))
  end
end

def heading(a) = "top-level #{a}"

p Blocks.run.length
p Blocks.run.map { |s| s.key }

# The same collision on the INSTANCE side, where the enclosing self is an
# object rather than a module.
class Sheet
  def fill
    rows = []
    row(rows, "a")
    row(rows, "b")
    rows
  end

  def row(rows, said)
    rows.push(Scenario.new(said))
  end
end

def row(x) = "top-level row"

p Sheet.new.fill.length
p Sheet.new.fill.map { |s| s.key }

# And the top-level method still answers when it is the one actually named.
p heading("x")
p row(1)
