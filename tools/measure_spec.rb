# frozen_string_literal: true

# What does an in-process compile cost, and how fast does the heap grow?
#
#   ruby -Ilib -Itest tools/measure_spec.rb <case or dir>... [--limit N]
#
# The whole question the spec road turns on: a fresh ruby per case pays
# the compiler's load every time, and one ruby compiling many pays it
# once but never gives its heap pages back. This walks a real area
# in one process, timing each compile and reading this process's
# resident size after it, so the recycle point is a measured number.

require "support/spec"
require "support/harness/case"
require_relative "convert"

limit = nil
if (i = ARGV.index("--limit"))
  limit = Integer(ARGV[i + 1])
  ARGV.slice!(i, 2)
end

cases = ARGV.flat_map { |a| File.directory?(a) ? Dir[File.join(a, "*.rb")].sort : [a] }
abort "usage: ruby -Ilib -Itest tools/measure_spec.rb <case or dir>... [--limit N]" if cases.empty?
cases = cases.first(limit) if limit

def rss_mb = Integer(`ps -o rss= -p #{Process.pid}`) / 1024.0

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

puts format("%-5s %-46s %8s %8s %9s", "n", "case", "secs", "rssMB", "verdict")
began = now
base = rss_mb
rows = []
cases.each_with_index do |rb, n|
  # The same reading a spec gets: the path the program answers to, its
  # own files, and the scrubbed answer it is held to.
  ex, why = Convert.read(File.expand_path(rb))
  (puts(format("%-5d %-46s %8s %8s %9s", n + 1, rb, "-", "-", "refused")); next) unless ex

  started = now
  out = Ze0::Spec.build_and_run(ex.source, path: ex.path || File.basename(rb), files: ex.files,
                                           argv: ex.directives.args, env: ex.directives.env.merge(ex.directives.zeo_env))
  took = now - started
  verdict = if !out.is_a?(Ze0::Spec::Result)
              out.first
            elsif out.stdout == Ze0::Spec.text(ex.expected.stdout) && out.stderr == Ze0::Spec.text(ex.expected.stderr)
              "matched"
            else
              "diverged"
            end
  rows << [took, rss_mb, verdict]
  puts format("%-5d %-46s %8.2f %8.1f %9s", n + 1, rb.delete_prefix("test/")[0, 46], took, rows.last[1], verdict)
end

total = now - began
times = rows.map(&:first).sort
puts
puts format("%d case(s) in %.1f s -- %.2f s each, median %.2f s", rows.size, total, total / rows.size, times[times.size / 2])
puts format("resident: %.0f MB at the start, %.0f MB at the end, %.2f MB a case",
            base, rows.last[1], (rows.last[1] - base) / rows.size)
rows.group_by(&:last).sort_by { |_, v| -v.size }.each { |what, v| puts format("  %-9s %d", what, v.size) }
