# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"

module Zr
  module Dev
    class GemCompat
      # `zr-dev gems sweep`: tries many gems, and writes one line for each
      # gem as it ends, then the count in each tier. As each gem ends, its
      # line goes into log/gems/sweep-<time>.log and its row into
      # log/gems/sweep-<time>.tsv, and with `--save` into gems/compat.tsv
      # too, where it replaces the row of the same gem. So a sweep that
      # stops keeps every row so far, and `tail -f` shows its progress.
      #
      # One gem at a time by default: a build can use 2 GB. `--jobs`
      # raises it. Ctrl-C stops the children.
      #
      # The trials build with this checkout, and a build fails when zr
      # changes under it: change zr only after the sweep.
      class Sweep < Base
        summary "Many gems, one line each, into a table"

        LOG = Dev.path("log/gems")
        usage "[GEM...] [--top N|FIRST..LAST] [--jobs N] [--save] [--corpus DIR] [--offline] [--build-only]"

        def defaults
          super
          @top = nil
          @jobs = nil
          @save = false
        end

        def options(o)
          super
          o.on("--top N|FIRST..LAST", "also the N most downloaded gems of gems/top.tsv, or those ranked FIRST to LAST") do |v|
            @top = Sweep.ranks(v) or fail!("--top takes N or FIRST..LAST, as 100 or 1001..2000, not #{v}")
          end
          o.on("--jobs N", Integer, "gems at a time (default 1)") { |v| @jobs = v }
          o.on("--save", "write the rows into gems/compat.tsv") { @save = true }
        end

        def run(argv)
          $stdout.sync = true
          words = words(argv)
          fail!("give gems, or --top N") if words.empty?
          requests = words.uniq.map { |word| request(word) }
          reference!

          base = File.join(LOG, "sweep-#{Time.now.strftime("%Y%m%d-%H%M%S")}")
          tables = [Gems::Table.new("#{base}.tsv")]
          tables << Gems::Table.new(Gems::Table.compat) if @save
          FileUtils.mkdir_p(LOG)
          File.open("#{base}.log", "w") do |log|
            log.sync = true
            say = ->(line) { [$stdout, log].each { |io| io.puts line } }
            say.call("#{requests.size} gems with zr #{Gems::Table.commit}; rows in #{tables.map { Dev.rel(_1.path) }.join(" and ")}")
            say.call(summary(sweep(requests, tables, say), requests.size))
          end
          true
        end

        # Tries each request on `@jobs` threads. On this thread, records
        # each result as it ends and says its line. Returns the results.
        def sweep(requests, tables, say)
          trial = trial()
          results = []
          start = now
          each = lambda do |(result, seconds)|
            results << result
            record(tables, result)
            say.call(format("[%d/%d] %s (%ds; %dm in all)", results.size, requests.size, result.line, seconds, (now - start) / 60))
          end
          Dev.parallel_map(requests, jobs: @jobs || 1, each: each) do |request|
            began = now
            [trial.call(request), now - began]
          end
          results
        rescue Interrupt
          Harness::Child.stop_all
          say.call("stopped after #{results.size} of #{requests.size} gems")
          results
        end

        def summary(results, wanted)
          counts = results.map(&:tier).tally
          tiers = [*Gems::TIERS.reverse, :skipped].filter_map { |tier| "#{counts[tier]} #{tier}" if counts[tier] }
          "#{results.size} of #{wanted} gems: #{tiers.join(", ")}"
        end

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # The gems of `argv`, then those of `--top`'s ranks. A name in the
        # list that no request can name is skipped, so it does not stop the
        # gems around it.
        def words(argv)
          return argv.dup unless @top

          top = top_list
          fail!("no gems/top.tsv; run `zr-dev gems top --refresh`") if top.empty?
          listed, odd = (top.keys[@top] || []).partition { |name| name.match?(Gems::NAME) }
          odd.each { |name| warn "zr-dev #{self.name}: skipped #{name.inspect} of gems/top.tsv: not a gem name this tool takes" }
          argv + listed
        end

        # The most downloaded gems, by rank (gems/top.tsv).
        def top_list = Gems::Top.read

        # The indexes into gems/top.tsv of `--top`'s ranks, which count
        # from 1: "100" is the first 100, and "1001..2000" the next 1000.
        def self.ranks(text)
          case text
          when /\A[1-9]\d*\z/ then 0...Integer(text)
          when /\A([1-9]\d*)\.\.([1-9]\d*)\z/ then (Integer($1) - 1)...Integer($2) if Integer($1) <= Integer($2)
          end
        end
      end
    end
  end
end
