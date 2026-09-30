# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"

module Zr
  module Dev
    class GemCompat
      # `zr-dev gems sweep`: tries many gems, and writes one line for each
      # gem as it ends, then the count in each tier. The rows go into a
      # new tmp/gems/sweep-<time>.tsv, or with `--save` into
      # gems/compat.tsv, where they replace the rows of the same gems.
      #
      # One gem at a time by default: a build can use 2 GB. `--jobs`
      # raises it. Ctrl-C stops the children and keeps the rows so far.
      class Sweep < Base
        summary "Many gems, one line each, into a table"
        usage "[GEM...] [--top N] [--jobs N] [--save] [--corpus DIR] [--offline]"

        def options(o)
          super
          o.on("--top N", Integer, "also the N most downloaded gems of gems/top.tsv") { |v| @top = v }
          o.on("--jobs N", Integer, "gems at a time (default 1)") { |v| @jobs = v }
          o.on("--save", "write the rows into gems/compat.tsv") { @save = true }
        end

        def run(argv)
          words = argv.dup
          if @top
            top = Gems::Top.read
            fail!("no gems/top.tsv; run `zr-dev gems top --refresh`") if top.empty?
            words.concat(top.keys.first(@top))
          end
          fail!("give gems, or --top N") if words.empty?
          requests = words.uniq.map { |word| request(word) }
          reference!

          table = Gems::Table.new(@save ? Gems::Table.compat : File.join(Gems::TMP, "sweep-#{Time.now.strftime("%Y%m%d-%H%M%S")}.tsv"))
          results = []
          begin
            sweep(requests) do |result|
              results << result
              puts result.line
            end
          rescue Interrupt
            Harness::Child.stop_all
            warn "zr-dev #{name}: stopped after #{results.size} of #{requests.size} gems"
          end
          summary(results)
          record(table, results) unless results.empty?
          true
        end

        # Tries each request on `@jobs` threads, and yields each result on
        # this thread.
        def sweep(requests)
          trial = Gems::Trial.new(resolver: resolver)
          queue = Queue.new
          requests.each { |request| queue << request }
          queue.close
          done = Queue.new
          workers = Array.new([@jobs || 1, requests.size].min) do
            Thread.new do
              while (request = queue.pop)
                done << trial.call(request)
              end
            rescue StandardError => e
              done << e
            end
          end
          requests.size.times do
            result = done.pop
            raise result if result.is_a?(Exception)

            yield result
          end
        ensure
          workers&.each(&:kill)
        end

        def summary(results)
          counts = results.map(&:tier).tally
          tiers = [*Gems::TIERS.reverse, :skipped].filter_map { |tier| "#{counts[tier]} #{tier}" if counts[tier] }
          puts "#{results.size} gems: #{tiers.join(", ")}"
        end
      end
    end
  end
end
