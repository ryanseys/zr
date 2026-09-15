# The size of what the backend writes, in instructions: the whole runtime
# through `Backend::Aarch64::Codegen`, with no linking and nothing run.
#
#   ruby -Ilib tools/codesize.rb            the total, and the twenty largest
#   ruby -Ilib tools/codesize.rb --all      every function, one a line
#   ruby -Ilib tools/codesize.rb <was.tsv>  the same against an earlier run
#
# A codegen change is worth what this number moves. The per-function table
# is there because a total hides a function that grew while others shrank.
require "ze0/zr"
require "ze0/backend/aarch64/codegen"
require "ze0/ir/passes"

all = ARGV.delete("--all")
was = ARGV.shift

runtime = Ze0::Zr.runtime
functions = runtime.functions.each { |f| Ze0::IR::Passes.prepare(f) }
defined = functions.map(&:name).to_set

began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sizes = functions.to_h do |f|
  [f.name, Ze0::Backend::Aarch64::Codegen.new(f, defined: defined).compile.bytes.bytesize / 4]
end
took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began

total = sizes.values.sum
if was
  before = File.readlines(was).to_h { |l| n, c = l.split("\t"); [n, c.to_i] }
  old = before.values.sum
  moved = sizes.filter_map do |name, now|
    then_ = before[name] or next
    [name, then_, now, now - then_] unless now == then_
  end
  moved.sort_by! { |(_, _, _, d)| d }
  puts format("%d -> %d instructions in %d functions (%+.2f%%), %d changed",
              old, total, sizes.size, 100.0 * (total - old) / old, moved.size)
  rows = all ? moved : moved.first(10) + moved.last(10)
  rows.uniq.each { |name, t, n, d| puts format("  %+6d  %6d -> %-6d %s", d, t, n, name) }
else
  puts format("%d instructions in %d functions, in %.1fs", total, sizes.size, took)
  table = all ? sizes.sort_by { |_, c| -c } : sizes.sort_by { |_, c| -c }.first(20)
  table.each { |name, count| puts format("  %6d  %s", count, name) }
end

File.write("tmp/codesize.tsv", sizes.map { |n, c| "#{n}\t#{c}\n" }.join)
warn "wrote tmp/codesize.tsv"
