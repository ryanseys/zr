# frozen_string_literal: true

require "json"
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
      # Each trial also compiles the C extensions among the gem and the
      # gems that it needs, with no gem code (Gems::CScan), and
      # log/gems/sweep-<time>.capi.jsonl gets their imports and what zr's
      # C API lacks of them. At the end the sweep ranks the functions that
      # the C API lacks by the number of swept gems that wait on each, and
      # writes the ranking to sweep-<time>.capi.txt. `--c-scan` does only
      # that: it finds each gem and scans its C, and builds and runs
      # nothing, so it writes no table rows.
      #
      # The trials build with this checkout, and a build fails when zr
      # changes under it: change zr only after the sweep.
      class Sweep < Base
        summary "Many gems, one line each, into a table"

        LOG = Dev.path("log/gems")
        usage "[GEM...] [--top N|FIRST..LAST] [--jobs N] [--save] [--corpus DIR] [--offline] [--build-only] [--c-scan]"

        # The functions and the extensions that the end of a sweep shows.
        SHOWN = 40

        def defaults
          super
          @top = nil
          @jobs = nil
          @save = false
          @c_scan = false
        end

        def options(o)
          super
          o.on("--top N|FIRST..LAST", "also the N most downloaded gems of gems/top.tsv, or those ranked FIRST to LAST") do |v|
            @top = Sweep.ranks(v) or fail!("--top takes N or FIRST..LAST, as 100 or 1001..2000, not #{v}")
          end
          o.on("--jobs N", Integer, "gems at a time (default 1)") { |v| @jobs = v }
          o.on("--save", "write the rows into gems/compat.tsv") { @save = true }
          o.on("--c-scan", "only scan the C extensions of each gem and the gems it needs; build and run nothing") { @c_scan = true }
        end

        def run(argv)
          $stdout.sync = true
          words = words(argv)
          fail!("give gems, or --top N") if words.empty?
          fail!("--c-scan writes no rows, so it takes no --save") if @c_scan && @save
          requests = words.uniq.map { |word| request(word) }
          reference! unless @c_scan

          base = File.join(LOG, "sweep-#{Time.now.strftime("%Y%m%d-%H%M%S")}")
          tables = @c_scan ? [] : [Gems::Table.new("#{base}.tsv")]
          tables << Gems::Table.new(Gems::Table.compat) if @save
          FileUtils.mkdir_p(LOG)
          File.open("#{base}.log", "w") do |log|
            log.sync = true
            say = ->(line) { [$stdout, log].each { |io| io.puts line } }
            File.open("#{base}.capi.jsonl", "w") do |capi|
              capi.sync = true
              files = [*tables.map(&:path), capi.path].map { |path| Dev.rel(path) }
              say.call("#{requests.size} gems with zr #{Gems::Table.commit}; rows in #{files.join(" and ")}")
              rows = @c_scan ? c_scan(requests, capi, say) : sweep(requests, tables, capi, say)
              say.call("stopped after #{rows.size} of #{requests.size} gems") if rows.size < requests.size
              say.call(summary(rows, requests.size)) unless @c_scan
              rank(rows.map { |row| [row.name, row.scans] }, "#{base}.capi.txt", say)
            end
          end
          true
        end

        # Tries each request on `@jobs` threads. On this thread, records
        # each result as it ends and says its line. Returns the results.
        def sweep(requests, tables, capi, say)
          trial = trial()
          each_done(requests, say, ->(result) { record(tables, result) }, capi) do |request|
            trial.call(request)
          end
        end

        # Scans the C of each request and the gems it needs. Returns a
        # Result for each, with only its name and its scans.
        def c_scan(requests, capi, say)
          trial = trial()
          each_done(requests, say, nil, capi) do |request|
            name, scans = trial.scan(request)
            Gems::Result.new(name: name, version: "", source: "", tier: :skipped, kind: "c-scan", detail: nil, log: nil, scans: scans)
          rescue Gems::Failure, Gem::Exception, SystemCallError, SocketError => e
            Gems::Result.new(name: request.label, version: "", source: "", tier: :fails, kind: "resolve",
                             detail: e.message.lines.first&.chomp, log: nil)
          end
        end

        # Runs the block for each request on `@jobs` threads. On this
        # thread, as each one ends: `record` gets its result, its scans go
        # into `capi`, and `say` gets its line. Returns the results so far.
        def each_done(requests, say, record, capi)
          results = []
          start = now
          each = lambda do |(result, seconds)|
            results << result
            record&.call(result)
            capi.puts(JSON.generate(name: result.name, version: result.version, tier: result.tier, scans: result.scans.map(&:to_h)))
            say.call(format("[%d/%d] %s%s (%ds; %dm in all)", results.size, requests.size, @c_scan ? c_line(result) : result.line,
                            @c_scan ? "" : c_note(result), seconds, (now - start) / 60))
          end
          Dev.parallel_map(requests, jobs: @jobs || 1, each: each) do |request|
            began = now
            [yield(request), now - began]
          end
          results
        rescue Interrupt
          Harness::Child.stop_all
          results
        end

        # A scan's line: the gem and what its C extensions lack.
        def c_line(result)
          return format("%-9s %s  %s", result.tier, result.name, result.detail) unless result.tier == :skipped
          return format("%-9s %s", "no C", result.name) if result.scans.empty?

          format("%-9s %s%s", "C", result.name, c_note(result))
        end

        # What a result's C extensions lack: `  C: nokogiri lacks 0`.
        def c_note(result)
          return "" if result.scans.empty?

          "  C: #{result.scans.map { |scan| lacks(scan) }.join(", ")}"
        end

        # `pg lacks 3: rb_copy_generic_ivar rb_gc_adjust_memory_usage
        # rb_locale_encindex`, or `nokogiri lacks 0 (35/36)`: the functions
        # that zr's C API lacks, and the files that compiled when not all
        # did. A function that `ruby` lacks too comes last, apart: it is no
        # gap of zr's. A scan with no compiled file found nothing to count.
        def lacks(scan, ruby = Gems::CScan::RUBY)
          return "#{scan.gem} has no C files" if scan.sources.zero?
          return "#{scan.gem} did not compile (0/#{scan.sources})" if scan.compiled.zero?

          missing = scan.missing(ruby)
          others = scan.ruby_lacks(ruby)
          files = " (#{scan.compiled}/#{scan.sources})" unless scan.complete?
          names = ": #{missing.join(" ")}" unless missing.empty?
          foreign = "; ruby lacks too: #{others.join(" ")}" unless others.empty?
          "#{scan.gem} lacks #{missing.size}#{files}#{names}#{foreign}"
        end

        # Writes the ranking of `rows` (CScan.rank) to `path` and says its
        # head.
        def rank(rows, path, say)
          ranking = Gems::CScan.rank(rows)
          lines = ["the C API functions that the swept gems wait on (swept gems that need each):",
                   *ranking.functions.map { |function, users| format("%5d  %-40s %s", users.size, function, users.first(6).join(" ")) },
                   "", "the C extensions that the swept gems need (gems that need each; files that compiled; functions it lacks):",
                   *ranking.extensions.map do |gem, users, scan|
                     format("%5d  %-24s %3d/%-3d %3d  %s", users.size, "#{gem} #{scan.version}", scan.compiled, scan.sources,
                            scan.missing.size, scan.missing.first(8).join(" "))
                   end]
          File.write(path, "#{lines.join("\n")}\n")
          functions = ranking.functions.size
          ["", *lines.first(SHOWN + 1)].each { |line| say.call(line) }
          say.call("... #{functions - SHOWN} more") if functions > SHOWN
          say.call("all of it, with the #{ranking.extensions.size} extensions: #{Dev.rel(path)}")
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
