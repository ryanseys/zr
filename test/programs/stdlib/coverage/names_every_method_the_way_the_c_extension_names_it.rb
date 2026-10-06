# Method coverage over the AOT instrumentation, against the C
# extension row for row. A row is made where the definition runs,
# so it carries that run's owner and name and the span of the
# `def` or the block behind it; the key is [owner, name, start
# line, start column, end line, end column].
#
# branching.rb holds the shapes the rule turns on: an `attr_reader`
# is no row, a `def` under a branch that never ran is absent, a
# singleton def's owner is the singleton class, and
# `define_method` is located at the block, not at the call. The
# rows come out in the order the C extension walks the heap in, so
# they are sorted here by where each one was written.
require "coverage"
Coverage.start(methods: true)
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
measured[:methods].sort_by { |(owner, name, *where), _| [where, name.to_s, owner.to_s] }.each do |key, count|
  puts "#{key.inspect} => #{count}"
end
