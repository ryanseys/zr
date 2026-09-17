# frozen_string_literal: true

# prism 1.9.0's own test suite (test/prism, extracted from ~/dev/prism into
# tmp/prism-1.9.0) on the Ruby port, each file beside its run on ruby's C
# extension (lib/ze0/harness/prism_diff.rb).
#
#   ruby tools/prism_upstream_tests.rb [--only GLOB] [--jobs N] [--show N]
#
# A file passes when it passes on the Ruby port or fails the same way on
# the C extension. Counts are tests/assertions/failures/errors/pendings/
# omissions; a file that returns before its tests (on a ruby whose own
# parser is prism) runs no tests on either backend. --only is a glob over paths such as prism/api/*_test.rb.
# The exit status is 1 when any file does not pass.
require "optparse"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ze0/harness/prism_diff"

only = nil
jobs = 3
show = 5
OptionParser.new do |o|
  o.on("--only GLOB") { |glob| only = glob }
  o.on("--jobs N", Integer) { |n| jobs = n.clamp(1, 3) }
  o.on("--show N", Integer) { |n| show = n }
end.parse!

diff = Ze0::Harness::PrismDiff
ruby = diff.upstream_tests(:ruby, only: only, jobs: jobs)
c = diff.upstream_tests(:c, only: only, jobs: jobs).to_h { |run| [run.file, run] }
failures = ruby.reject { |run| run.passed? || run.counts == c.fetch(run.file).counts }
ruby.each do |run|
  expected = c.fetch(run.file)
  mark = failures.include?(run) ? "FAIL" : "ok  "
  counts = ->(test_run) { test_run.tests ? test_run.counts.join("/") : "no tests run" }
  puts format("%s %-50s ruby %-28s c %s", mark, run.file, counts.(run), counts.(expected))
end
failures.first(show).each { |run| puts "\n== #{run.file}\n#{run.output.lines.last(60).join}" }
puts "#{ruby.size - failures.size} of #{ruby.size} files pass"
exit(failures.empty? ? 0 : 1)
