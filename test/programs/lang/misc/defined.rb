# frozen_string_literal: true

# `defined?(expr)` answers ruby's prose for what the expression IS, or
# nil when it is not there. What is inside never runs for its value: a
# method is asked about rather than called, and an assignment does not
# assign. The parts that ARE evaluated -- a call's receiver, a constant's
# scope -- run under a landing that swallows a raise and answers nil.

x = 1
p defined?(x)
p defined?(nope)
p defined?(self)
p defined?(nil), defined?(true), defined?(false)
p defined?([1, 2]), defined?("s"), defined?(:s), defined?(1..2)
p defined?(if x then 1 end)

# The assignment does not run.
p defined?(y = 2)
p defined?(y)

p defined?(String)
p defined?(Missing)
p defined?(String::Comparable)
p defined?(Missing::Thing)

p defined?($stdout)
p defined?($never_set_anywhere)

p defined?(puts)
p defined?("a".upcase)
p defined?("a".nope)
p defined?(nothing.here)
p defined?(1 + 1)
p defined?(x.between?(0, 2))

class Holder
  def initialize = @set = 1

  def report
    [defined?(@set), defined?(@unset), defined?(helper), defined?(self.helper)]
  end

  private

  def helper = 1
end

p Holder.new.report

def with_block = defined?(yield)
p with_block { 1 }
p with_block

# The receiver is evaluated, so its side effect happens once; the method
# is not called at all.
seen = []
answer = defined?(seen.push(1).nope)
p answer, seen
