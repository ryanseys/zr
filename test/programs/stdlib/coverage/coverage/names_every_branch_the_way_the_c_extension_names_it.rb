# Branch coverage over the AOT instrumentation, against the C
# extension row for row: the key is [kind, id, start line, start
# column, end line, end column] with 0-based columns, and the ids
# run from 0 a file, a root then its sides.
#
# branching.rb carries every kind CRuby records one for and the
# ones it records none for. `||` and `&&` are not branches, an
# `elsif` is a nested :if at the outer :else's location, `unless`
# lists :else before :then, a `case/in` gets an :else at the case's
# own location with nothing in the source to put there, and `&.`
# puts both sides where the call stands. A predicate ruby's
# compiler decides -- the last `if` here -- keeps its branch, and
# one it can fold away would keep none.
require "coverage"
Coverage.start(branches: true)
require_relative "coverage/branching"

cov_ladder(20)
cov_ladder(7)
cov_unless(nil)
cov_ternary(2)
cov_when(1)
cov_in(1)
cov_while(1)
cov_until(0)
cov_safe("a")
cov_ops(1, 2)
CovShapes.new.instance_one

measured = Coverage.result.find { |path, _| File.basename(path) == "branching.rb" }.last
measured[:branches].each do |root, sides|
  puts root.inspect
  sides.each { |side, count| puts "  #{side.inspect} => #{count}" }
end
