# frozen_string_literal: true

# The size of what the backend writes, in instructions: the whole
# runtime through `Backend::Aarch64::Codegen`, with no linking and
# nothing run.
#
#   rake codesize             the total, and the twenty largest
#   rake 'codesize[--all]'    every function, one a line
#   rake 'codesize[was.tsv]'  the same against an earlier run
#
# A codegen change is worth what this number moves. The per-function
# table is there because a total hides a function that grew while others
# shrank. Every run writes `tmp/codesize.tsv`, which is what a later one
# is given to compare against.

require "ze0/zr"
require "ze0/backend/aarch64/codegen"
require "ze0/ir/passes"

module Codesize
  module_function

  def report(argv)
    all = argv.delete("--all")
    was = argv.shift

    runtime = Ze0::Zr.runtime
    functions = Ze0::IR::Passes.inline(runtime.functions).each { |f| Ze0::IR::Passes.prepare(f) }
    defined = functions.map(&:name).to_set

    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sizes = functions.to_h do |f|
      [f.name, Ze0::Backend::Aarch64::Codegen.new(f, defined: defined).compile.bytes.bytesize / 4]
    end
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began

    was ? against(sizes, was, all) : table(sizes, took, all)

    File.write("tmp/codesize.tsv", sizes.map { |n, c| "#{n}\t#{c}\n" }.join)
    warn "wrote tmp/codesize.tsv"
  end

  def table(sizes, took, all)
    puts format("%d instructions in %d functions, in %.1fs", sizes.values.sum, sizes.size, took)
    rows = sizes.sort_by { |_, c| -c }
    (all ? rows : rows.first(20)).each { |name, count| puts format("  %6d  %s", count, name) }
  end

  def against(sizes, was, all)
    total = sizes.values.sum
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
  end
end

desc "Count the instructions the backend writes for the runtime: rake 'codesize[--all]'"
task(:codesize, [:opts]) { |_, args| Codesize.report(args[:opts].to_s.split) }
