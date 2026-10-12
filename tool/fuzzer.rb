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
          "reduce" => ["Make a failing Ruby file small, while it still fails the same way", -> { Reduce }],
          "recheck" => ["Check the smallest case of each open bucket again, and mark the fixed ones", -> { Recheck }],
          "replay" => ["Check one case again, and show how ruby and zr differ", -> { Replay }],
          "gen" => ["Print the program of a seed, or check the generator on ruby", -> { Gen }],
          "report" => ["List the buckets of log/fuzz", -> { Report }]
        )

        # The parts that `run` and the commands like it share: the options
        # of the oracle, and the start of a builder on a pinned zr.
        module Pinned
          def pinned_defaults
            @jobs = nil
            @coverage = false
            @budget = nil
          end

          def pinned_options(o)
            o.on("-j JOBS", Integer, "programs at a time (default: what the memory affords)") { |v| @jobs = v }
            o.on("--coverage", "measure the compiler lines that each build runs") { @coverage = true }
            o.on("--reduce-budget N", Integer, "checks for the reduction of one case (default #{Dev::Fuzz::Reducer::BUDGET})") do |v|
              @budget = v
            end
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

          # Makes a Reducer for one case: it checks with the oracle, with no
          # second run, on half of the jobs, as other cases run beside it.
          def reducer_for(oracle)
            lambda do
              Dev::Fuzz::Reducer.new(check: ->(source) { oracle.check(source, confirm: false) }, jobs: [jobs / 2, 1].max,
                                     budget: @budget || Dev::Fuzz::Reducer::BUDGET)
            end
          end

          # Facts for each case record.
          def run_meta = { fuzzer: Dev::Fuzz::VERSION, zr_version: Suite.zr_version, ruby_revision: RUBY_REVISION }
        end

        # `zr-dev fuzz run`.
        class Run < Command
          include Pinned

          summary "Fuzz: check programs until the time or the count is up"
          usage "[--time 30m | --count N] [-j N] [--seed S] [--mode gen,mutate,meta,junk,seed] [--packs a,b] [--seeds DIR,...]"
          host_ruby!

          # Where programs come from, and how often each one comes when a
          # run has more than one. `seed` runs the seed files as they are,
          # each one once, so it is only on when asked for.
          WEIGHTS = { "gen" => 50, "mutate" => 30, "meta" => 15, "junk" => 5 }.freeze
          MODES = [*WEIGHTS.keys, "seed"].freeze

          def defaults
            pinned_defaults
            @time = nil
            @count = nil
            @seed = nil
            @modes = nil
            @seeds = nil
            @reduce = true
            @packs = nil
          end

          def options(o)
            pinned_options(o)
            o.on("--time SPAN", "how long to run: 90s, 30m, 2h (default 30m)") { |v| @time = span(v) }
            o.on("--count N", Integer, "how many programs to check") { |v| @count = v }
            o.on("--seed S", Integer, "the seed of the run (default: random)") { |v| @seed = v }
            o.on("--mode LIST", Array, "where programs come from: #{MODES.join(", ")}") { |v| @modes = v }
            o.on("--no-reduce", "keep each failing program as it is") { @reduce = false }
            o.on("--packs LIST", Array, "only these packs in generated programs") { |v| @packs = v }
            o.on("--seeds LIST", Array, "seed files or directories (default test/programs, log/fuzz/corpus)") do |v|
              @seeds = v.map { |d| File.expand_path(d) }
            end
          end

          def run(_argv)
            Dev.pinned!(name)
            modes = @modes || WEIGHTS.keys
            unknown = modes - MODES
            fail!("no mode #{unknown.join(", ")}; the modes are #{MODES.join(", ")}") unless unknown.empty?
            seed = @seed || Random.new_seed % 1_000_000
            store = Dev::Fuzz::Store.new
            rng = Random.new(seed)
            sources = sources(modes, rng, store)
            deadline = @count && !@time ? nil : Timing.now + (@time || 30 * 60)
            puts "zr-dev fuzz: run #{store.run}, seed #{seed}, #{jobs} job(s), modes #{modes.join(", ")}; log #{Dev.rel(store.log_path)}"
            with_oracle(store) do |oracle|
              triage = Dev::Fuzz::Triage.new(store: store, reducer: @reduce ? reducer_for(oracle) : nil,
                                             meta: run_meta.merge(seed: seed))
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

          # [source, weight] for each mode.
          def sources(modes, rng, store)
            dirs = @seeds || Dev::Fuzz::Corpus::DEFAULT
            files = Dev::Fuzz::Corpus.files(dirs)
            fail!("no seed files in #{dirs.join(", ")}") if files.empty?
            modes.map do |mode|
              case mode
              when "seed" then [Dev::Fuzz::SeedSource.new(files, rng), 1]
              when "mutate"
                kept = Dir[store.path("corpus", "*.rb")]
                mutator = Dev::Fuzz::Mutator.new(seeds: ->(r) { File.binread(files.sample(random: r)) },
                                                 generator: ->(r) { Dev::Fuzz::Gen.snippet(r.rand(2**31)) })
                [Dev::Fuzz::MutateSource.new(files, mutator: mutator, kept: kept), WEIGHTS.fetch(mode)]
              when "gen" then [Dev::Fuzz::GenSource.new(only: @packs), WEIGHTS.fetch(mode)]
              when "meta"
                snippet = ->(r) { Dev::Fuzz::Gen.snippet(r.rand(2**31)) }
                [Dev::Fuzz::MetaSource.new(base: Dev::Fuzz::GenSource.new(only: @packs), generator: snippet), WEIGHTS.fetch(mode)]
              when "junk" then [Dev::Fuzz::JunkSource.new(files), WEIGHTS.fetch(mode)]
              end
            end
          end

          # Seconds in a span such as "90s", "30m", "2h" or "45".
          def span(text)
            parts = text.match(/\A(\d+)([smh]?)\z/)&.captures or fail!("give a span such as 90s, 30m or 2h, not #{text}")
            n, unit = parts
            Integer(n) * { "" => 1, "s" => 1, "m" => 60, "h" => 3600 }.fetch(unit)
          end
        end

        # `zr-dev fuzz reduce FILE`: reduces any Ruby file that fails in
        # zr, from the fuzzer, a suite or a gem, and writes the result to
        # log/fuzz/reduced/.
        class Reduce < Command
          include Pinned

          summary "Make a failing Ruby file small, while it still fails the same way"
          usage "<file.rb> [-j N] [--reduce-budget N]"
          host_ruby!

          def defaults = pinned_defaults

          def options(o) = pinned_options(o)

          def run(argv)
            Dev.pinned!(name)
            file = argv.first or fail!("give a Ruby file")
            fail!("no such file: #{file}") unless File.file?(file)
            source = File.binread(file)
            store = Dev::Fuzz::Store.new
            with_oracle(store) do |oracle|
              result = oracle.check(source)
              unless result.failure?
                puts "#{file}: #{result.verdict.kind}#{" (#{result.verdict.detail})" if result.invalid?}; nothing to reduce"
                return true
              end
              puts "#{file}: #{result.verdict.kind}: #{result.verdict.detail[0, 150]}"
              reducer = reducer_for(oracle).call
              small, final, = reducer.reduce(source, result)
              out = store.path("reduced", File.basename(file).sub(/(\.rb)?\z/, ".rb"))
              FileUtils.mkdir_p(File.dirname(out))
              File.binwrite(out, small)
              puts "#{Dev.rel(out)}: #{small.bytesize} of #{source.bytesize} bytes after #{reducer.checks} check(s); " \
                   "#{final.verdict.kind}"
            end
            true
          end
        end

        # `zr-dev fuzz recheck`: checks the smallest case of each open
        # bucket (or of the given buckets) with the zr of the checkout. A
        # case that zr now passes marks its bucket fixed at this version.
        class Recheck < Command
          include Pinned

          summary "Check the smallest case of each open bucket again, and mark the fixed ones"
          usage "[bucket...] [-j N]"
          host_ruby!

          def defaults = pinned_defaults

          def options(o) = pinned_options(o)

          def run(argv)
            Dev.pinned!(name)
            store = Dev::Fuzz::Store.new
            open = store.buckets.select { |b, r| (argv.empty? ? r["status"] == "open" : argv.include?(b)) && r["smallest"] }
            if open.empty?
              puts "zr-dev fuzz: no bucket to check"
              return true
            end
            fixed = 0
            with_oracle(store) do |oracle|
              version = Suite.zr_version[0, 12]
              Dev.parallel_map(open.to_a, jobs: jobs, each: lambda { |(bucket, verdict)|
                if verdict.same?
                  store.mark(bucket, "fixed@#{version}")
                  fixed += 1
                end
                puts "#{bucket}: #{verdict.same? ? "FIXED" : verdict.kind}"
              }) do |bucket, record|
                [bucket, oracle.check(File.binread(Dev.path(record["smallest"]["path"]))).verdict]
              end
            end
            puts "#{fixed} of #{open.size} bucket(s) fixed"
            true
          end
        end

        # `zr-dev fuzz replay ID`: checks one case again, and prints the
        # diff of the answers.
        class Replay < Command
          include Pinned

          summary "Check one case again, and show how ruby and zr differ"
          usage "<case id | file.rb>"
          host_ruby!

          def defaults = pinned_defaults

          def options(o) = pinned_options(o)

          def run(argv)
            Dev.pinned!(name)
            id = argv.first or fail!("give a case id or a file")
            store = Dev::Fuzz::Store.new
            file = File.file?(id) ? id : Dir[store.path("cases", "*", "#{id}.rb")].first
            fail!("no case #{id} in #{Dev.rel(store.path("cases"))}") unless file
            @jobs ||= 1
            with_oracle(store) do |oracle|
              result = oracle.check(File.binread(file))
              puts "#{Dev.rel(File.expand_path(file))}: #{result.verdict.kind}: #{result.verdict.detail}"
              puts Dev::Fuzz::Store.diff(result) unless result.same?
              return result.same?
            end
          end
        end

        # `zr-dev fuzz gen`: prints the program of a seed, or checks the
        # generator on ruby alone (`--check N`): how many programs end
        # within the limit, give ruby the same answer twice, and how often
        # a unit raises (an error that the writer did not mean is a fault
        # of the writer).
        class Gen < Command
          summary "Print the program of a seed, or check the generator on ruby"
          usage "[--seed S] [--packs a,b] [--check N] [-j N]"
          host_ruby!

          def defaults
            @seed = 1
            @packs = nil
            @check = nil
            @jobs = nil
          end

          def options(o)
            o.on("--seed S", Integer, "the seed of the program (default 1)") { |v| @seed = v }
            o.on("--packs LIST", Array, "only these packs: #{Dev::Fuzz::Swarm::PACKS.keys.join(", ")}") { |v| @packs = v }
            o.on("--check N", Integer, "run N programs on ruby, twice each, and report") { |v| @check = v }
            o.on("-j JOBS", Integer, "programs at a time for --check") { |v| @jobs = v }
          end

          def run(_argv)
            unknown = (@packs || []) - Dev::Fuzz::Swarm::PACKS.keys
            fail!("no pack #{unknown.join(", ")}") unless unknown.empty?
            unless @check
              print Dev::Fuzz::Gen.program(@seed, only: @packs).first
              return true
            end

            Dev.pinned!(name)
            rows = check
            report(rows)
            rows.all? { |_, _, answer, same| answer.code.is_a?(Integer) && same }
          end

          UNIT_ERROR = /\Au\d+: ([A-Z]\w*(?:::\w+)*): (.*)/

          def check
            oracle = Dev::Fuzz::Oracle.new(builder: nil, work: Dev.path("tmp/fuzz/work/gen-check-#{Process.pid}"))
            seeds = (@seed...(@seed + @check)).to_a
            Dev.parallel_map(seeds, jobs: @jobs || Test::Workers.size) do |seed|
              source, swarm = Dev::Fuzz::Gen.program(seed, only: @packs)
              one = oracle.ruby_only(source)
              two = oracle.ruby_only(source)
              [seed, swarm, one, Dev::Fuzz::Classify.parts(one) == Dev::Fuzz::Classify.parts(two)]
            end
          ensure
            FileUtils.rm_rf(Dev.path("tmp/fuzz/work/gen-check-#{Process.pid}"))
          end

          def report(rows)
            ended = rows.count { |_, _, a, _| a.code.is_a?(Integer) }
            same = rows.count { |_, _, a, s| a.code.is_a?(Integer) && s }
            lines = rows.flat_map { |_, _, a, _| Dev::Fuzz::Classify.text(a.stdout).lines }
            units = lines.count { |l| l.match?(/\Au\d+\.\d+[: ]/) }
            errors = lines.filter_map { |l| l.match(UNIT_ERROR) }
            puts "#{rows.size} program(s): #{ended} ended in time, #{same} gave ruby the same answer twice"
            puts "#{units} shown value(s), #{errors.size} unit(s) stopped by an error"
            rows.reject { |_, _, a, s| a.code.is_a?(Integer) && s }.first(10).each do |seed, _, a, s|
              puts "  seed #{seed}: #{a.code.is_a?(Integer) ? "two answers" : a.code}#{" (twice the same)" if s}"
            end
            puts "the errors that stop units most often:"
            errors.map { |m| "#{m[1]}: #{Dev::Fuzz::Classify.template(m[2])[0, 90]}" }.tally.sort_by { -_2 }.first(25).each do |e, n|
              puts format("  %5d  %s", n, e)
            end
            statuses = rows.map { |_, _, a, _| a.code }.tally.sort_by { -_2 }
            puts "exit statuses: #{statuses.map { |c, n| "#{c} #{n}" }.join(", ")}"
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
