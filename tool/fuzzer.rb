# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "lib/zr/dev/fuzz"

module Zr
  module Dev
    module Commands
      # `zr-dev fuzz`: a differential fuzzer. It writes Ruby programs (or
      # takes them from a corpus), runs each one under ruby 4.0.7 and as a
      # zr binary, and keeps each difference as a small case in
      # log/fuzz/cases/, one bucket for each gap.
      #
      #   zr-dev fuzz run --time 30m           fuzz for 30 minutes
      #   zr-dev fuzz run --mode seed --seeds ~/dev/spinel/test
      #   zr-dev fuzz report                   the open buckets
      #
      # A run holds the suite lock and builds with a copy of zr
      # (tmp/suite/zr), so the checkout can change while it runs.
      class Fuzz < Group
        summary "Write Ruby programs, run them in ruby and in zr, and keep each difference"
        commands(
          "run" => ["Fuzz: check programs until the time or the count is up", -> { Run }],
          "report" => ["List the buckets of log/fuzz", -> { Report }]
        )

        # The parts that `run` and the commands like it share: the options
        # of the oracle, and the start of a builder on a pinned zr.
        module Pinned
          def pinned_defaults
            @jobs = nil
            @coverage = false
          end

          def pinned_options(o)
            o.on("-j JOBS", Integer, "programs at a time (default: what the memory affords)") { |v| @jobs = v }
            o.on("--coverage", "measure the compiler lines that each build runs") { @coverage = true }
          end

          def jobs = [@jobs || Test::Workers.size, 1].max

          # Takes the suite lock, pins zr, starts the builder and the
          # oracle, and yields them with the store.
          def with_oracle(store)
            Suite.lock! do
              Suite.pin!
              builder = Dev::Fuzz::BuilderClient.new(pin: Suite::PIN, jobs: jobs, coverage: @coverage,
                                                     log: store.path("runs", "#{store.run}.builder.log").tap { FileUtils.mkdir_p(File.dirname(_1)) })
              oracle = Dev::Fuzz::Oracle.new(builder: builder, work: Dev.path("tmp/fuzz/work/#{store.run}"))
              yield oracle
            ensure
              builder&.close
              FileUtils.rm_rf(Dev.path("tmp/fuzz/work/#{store.run}"))
            end
          end

          # Facts for each case record.
          def run_meta = { fuzzer: Dev::Fuzz::VERSION, zr_version: Suite.zr_version, ruby_revision: RUBY_REVISION }
        end

        # `zr-dev fuzz run`.
        class Run < Command
          include Pinned

          summary "Fuzz: check programs until the time or the count is up"
          usage "[--time 30m | --count N] [-j N] [--seed S] [--mode seed] [--seeds DIR,...]"
          host_ruby!

          MODES = %w[seed].freeze

          def defaults
            pinned_defaults
            @time = nil
            @count = nil
            @seed = nil
            @modes = nil
            @seeds = nil
          end

          def options(o)
            pinned_options(o)
            o.on("--time SPAN", "how long to run: 90s, 30m, 2h (default 30m)") { |v| @time = span(v) }
            o.on("--count N", Integer, "how many programs to check") { |v| @count = v }
            o.on("--seed S", Integer, "the seed of the run (default: random)") { |v| @seed = v }
            o.on("--mode LIST", Array, "where programs come from: #{MODES.join(", ")}") { |v| @modes = v }
            o.on("--seeds LIST", Array, "seed files or directories (default test/programs, log/fuzz/corpus)") do |v|
              @seeds = v.map { |d| File.expand_path(d) }
            end
          end

          def run(_argv)
            Dev.pinned!(name)
            modes = @modes || MODES
            unknown = modes - MODES
            fail!("no mode #{unknown.join(", ")}; the modes are #{MODES.join(", ")}") unless unknown.empty?
            seed = @seed || Random.new_seed % 1_000_000
            store = Dev::Fuzz::Store.new
            rng = Random.new(seed)
            sources = []
            if modes.include?("seed")
              files = Dev::Fuzz::Corpus.files(@seeds || Dev::Fuzz::Corpus::DEFAULT)
              fail!("no seed files in #{(@seeds || Dev::Fuzz::Corpus::DEFAULT).join(", ")}") if files.empty?
              sources << [Dev::Fuzz::SeedSource.new(files, rng), 1]
            end
            deadline = @count && !@time ? nil : Timing.now + (@time || 30 * 60)
            puts "zr-dev fuzz: run #{store.run}, seed #{seed}, #{jobs} job(s), modes #{modes.join(", ")}; log #{Dev.rel(store.log_path)}"
            with_oracle(store) do |oracle|
              triage = Dev::Fuzz::Triage.new(store: store, meta: run_meta.merge(seed: seed))
              engine = Dev::Fuzz::Engine.new(oracle: oracle, store: store, triage: triage, sources: sources, jobs: jobs,
                                             seed: seed, deadline: deadline, count: @count)
              old = Signal.trap("INT") { engine.stop! }
              stats = engine.run
              Signal.trap("INT", old)
              store.save_coverage
              store.finish(stats)
              puts "zr-dev fuzz: #{stats.map { |k, v| "#{k} #{v}" }.join(", ")}"
              puts "zr-dev fuzz: cases in #{Dev.rel(store.path("cases"))}; `zr-dev fuzz report` lists the buckets"
            end
            true
          end

          # Seconds in a span such as "90s", "30m", "2h" or "45".
          def span(text)
            parts = text.match(/\A(\d+)([smh]?)\z/)&.captures or fail!("give a span such as 90s, 30m or 2h, not #{text}")
            n, unit = parts
            Integer(n) * { "" => 1, "s" => 1, "m" => 60, "h" => 3600 }.fetch(unit)
          end
        end

        # `zr-dev fuzz report`.
        class Report < Command
          summary "List the buckets of log/fuzz"
          usage "[--all]"

          def defaults = @all = false

          def options(o) = o.on("--all", "also the fixed and the known buckets") { @all = true }

          def run(_argv)
            buckets = Dev::Fuzz::Store.new.buckets
            shown = buckets.select { |_, r| @all || r["status"] == "open" }
            if shown.empty?
              puts "zr-dev fuzz: no #{"open " unless @all}buckets in #{Dev.rel(Dev::Fuzz::Store::ROOT)}"
              return true
            end
            shown.sort_by { |_, r| [-r["count"], r.dig("smallest", "size") || 0] }.each do |bucket, r|
              puts "#{bucket}  #{r["count"]}x  #{r["status"]}#{"  layer #{r["layer"]}" if r["layer"]}"
              puts "    #{r["key"][0, 150]}"
              puts "    #{r.dig("smallest", "path")} (#{r.dig("smallest", "size")} bytes)" if r["smallest"]
            end
            by_kind = shown.values.group_by { |r| r["kind"] }.transform_values(&:size)
            puts "#{shown.size} bucket(s): #{by_kind.sort_by { |_, n| -n }.map { |k, n| "#{k} #{n}" }.join(", ")}"
            true
          end
        end
      end
    end
  end
end
