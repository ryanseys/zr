# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # Counts the instructions that the backend writes for the whole
    # runtime through `Backend::Aarch64::Codegen`. It does not link or run
    # anything.
    #
    #   zr-dev codesize                     the total, and the twenty largest
    #   zr-dev codesize --all               every function, one on each line
    #   zr-dev codesize --against was.tsv   the same, compared with an earlier run
    #
    # Use this number to measure a codegen change. The table for each
    # function is necessary because a total can hide a function that grew
    # while others shrank. Each run writes `tmp/codesize.tsv`; give that
    # file to a later run to compare.
    class Codesize < Command
      summary "Count the instructions the backend writes for the runtime"
      usage "[--all] [--against FILE]"

      OUT = Dev.path("tmp/codesize.tsv")

      def defaults
        @all = false
        @was = nil
      end

      def options(o)
        o.on("--all", "every function, not only the largest") { @all = true }
        o.on("--against FILE", "compare with the file an earlier run wrote") { |v| @was = v }
      end

      def run(_argv)
        require_relative "../lib/zr/runtime"
        require_relative "../lib/zr/backend/aarch64/codegen"
        require_relative "../lib/zr/ir/passes"

        functions = IR::Passes.inline(Runtime.for.functions).each { |f| IR::Passes.prepare(f) }
        defined = functions.to_set(&:name)

        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sizes = functions.to_h do |f|
          [f.name, Backend::Aarch64::Codegen.new(f, defined: defined).compile.bytes.bytesize / 4]
        end
        took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began

        @was ? against(sizes) : table(sizes, took)
        Paths.write_atomic(OUT, sizes.map { |n, c| "#{n}\t#{c}\n" }.join)
        warn "wrote #{Dev.rel(OUT)}"
      end

      def table(sizes, took)
        puts format("%d instructions in %d functions, in %.1fs", sizes.values.sum, sizes.size, took)
        rows = sizes.sort_by { |_, c| -c }
        (@all ? rows : rows.first(20)).each { |name, count| puts format("  %6d  %s", count, name) }
      end

      def against(sizes)
        total = sizes.values.sum
        before = File.readlines(@was).to_h do |line|
          name, count = line.split("\t")
          [name, count.to_i]
        end
        old = before.values.sum
        moved = sizes.filter_map do |name, now|
          was = before[name] or next
          [name, was, now, now - was] unless now == was
        end
        moved.sort_by! { |(_, _, _, d)| d }
        puts format("%d -> %d instructions in %d functions (%+.2f%%), %d changed",
                    old, total, sizes.size, 100.0 * (total - old) / old, moved.size)
        rows = @all ? moved : moved.first(10) + moved.last(10)
        rows.uniq.each { |name, t, n, d| puts format("  %+6d  %6d -> %-6d %s", d, t, n, name) }
      end
    end
  end
end
