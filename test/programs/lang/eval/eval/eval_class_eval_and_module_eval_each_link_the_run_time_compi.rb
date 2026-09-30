# frozen_string_literal: true

# The verbs that run a STRING of ruby. There is nothing for the compile
# to see, so the sidecar asks the backend to link the run-time compiler
# and the string is compiled where it runs.

p eval("1 + 2")
p eval("[1, 2].map { |n| n * 3 }")

# `class_eval` installs into the class it is called on.
class Counter
  def initialize = @n = 0
end
Counter.class_eval("def bump = @n += 1")
c = Counter.new
c.bump
p c.bump

# `module_eval` reaches a module's own singleton.
module Tools; end
Tools.module_eval("def self.twice(x) = x * 2")
p Tools.twice(21)

# `instance_eval` runs with the receiver as `self`, so a `def` there is
# that one object's.
o = Object.new
o.instance_eval("def only_mine = :mine")
p o.only_mine
p(o.instance_eval("self") == o)

# A string that does not parse raises where the eval stands.
begin
  eval("1 +")
rescue SyntaxError
  puts "SyntaxError"
end
