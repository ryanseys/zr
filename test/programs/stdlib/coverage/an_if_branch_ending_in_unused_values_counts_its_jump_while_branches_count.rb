# Under branch coverage, CRuby's `if` branch ends in a jump over the
# else's counter, given or not. When the branch's last statements are
# values that nothing uses, they compile to nothing and their :line
# event goes to that jump, on the `if` (or `elsif`) line, so the line
# counts once more for each run of the branch. Without branch coverage
# there is no such jump. `unless`, `case` and a branch whose value is
# used are as without it.
require "coverage"

path = File.expand_path("branch_jumps.rb", __dir__)
Coverage.start(lines: true, branches: true)
load path
p Coverage.result.fetch(path)[:lines]
Coverage.start(lines: true)
load path
p Coverage.result.fetch(path)[:lines]
Coverage.start(:all)
load path
result = Coverage.result.fetch(path)
p result[:lines], result[:branches].size
