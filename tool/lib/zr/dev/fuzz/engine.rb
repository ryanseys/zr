# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # The loop of `zr-dev fuzz run`: `jobs` threads take candidates from
      # the sources, check each one with the oracle, and give each
      # failure to the triage, which reduces it and writes its case. The
      # loop stops at the deadline, after `count` programs, when every
      # source is empty, or at Ctrl-C.
      class Engine
        # How often the status line prints, in seconds.
        EVERY = 10

        # The memory that must be free before a thread takes more work.
        FREE = 3 << 30

        attr_reader :stats

        # `sources` is a list of [source, weight]. A source answers
        # `next_candidate(rng)`, or nil when it has no more.
        def initialize(oracle:, store:, triage:, sources:, jobs:, seed:, deadline: nil, count: nil, out: $stdout)
          @oracle = oracle
          @store = store
          @triage = triage
          @sources = sources
          @jobs = jobs
          @seed = seed
          @deadline = deadline
          @count = count
          @out = out
          @lock = Mutex.new
          @taken = 0
          @stop = false
          @kinds = Hash.new(0)
          @stats = { programs: 0, valid: 0, same: 0, failures: 0, new_buckets: 0, known: 0, coverage: 0 }
        end

        def stop! = @stop = true

        def run
          began = Timing.now
          workers = Array.new(@jobs) { Thread.new { work } }
          until workers.none?(&:alive?)
            workers.each { |t| t.join(EVERY) }
            status(began)
          end
          workers.each(&:value)
          seconds = Timing.now - began
          @stats.merge(seconds: seconds.round, per_second: (@stats[:programs] / [seconds, 1].max).round(2),
                       coverage: @store.coverage.size)
        end

        private

        def work
          until @stop
            n = take or break
            wait_for_memory
            rng = Random.new((@seed * 1_000_003) + n)
            candidate = pick(rng) or break
            result = @oracle.check(candidate.source)
            tally(candidate, result)
          end
        end

        # The number of the next program, or nil when the run is over.
        def take
          @lock.synchronize do
            return nil if @stop || (@count && @taken >= @count) || (@deadline && Timing.now >= @deadline)

            @taken += 1
          end
        end

        # A candidate from a source chosen by weight. A source with no more
        # candidates leaves the list; nil when none is left.
        def pick(rng)
          loop do
            source = @lock.synchronize do
              live = @sources.reject { |_, w| w <= 0 }
              return nil if live.empty?

              roll = rng.rand * live.sum { |_, w| w }
              live.find { |_, w| (roll -= w) <= 0 }&.first || live.last.first
            end
            candidate = source.next_candidate(rng)
            return candidate if candidate

            @lock.synchronize { @sources.reject! { |s, _| s.equal?(source) } }
          end
        end

        def wait_for_memory
          free = Native::Parallel.available_bytes
          while free && free < FREE && !@stop
            sleep 2
            free = Native::Parallel.available_bytes
          end
        end

        def tally(candidate, result)
          kind = result.verdict.kind
          @lock.synchronize do
            @stats[:programs] += 1
            @kinds[kind] += 1
            next if result.invalid?

            @stats[:valid] += 1
            @stats[:same] += 1 if result.same?
            @stats[:failures] += 1 if result.failure?
          end
          fresh = result.build ? @store.cover(result.build.lines || []) : []
          @store.keep(candidate.source) if result.same? && !fresh.empty? && candidate.origin != "junk"
          return unless result.failure?

          outcome = @triage.call(candidate, result)
          @lock.synchronize do
            @stats[:known] += 1 if outcome == :known
            @stats[:new_buckets] += 1 if outcome == :new
          end
          return unless outcome == :new

          line = "NEW #{result.verdict.kind}: #{result.verdict.detail[0, 150]} (#{candidate.origin})"
          @store.log(line)
          @lock.synchronize { @out.puts(line) }
        end

        def status(began)
          seconds = [Timing.now - began, 1].max
          line = @lock.synchronize do
            s = @stats
            valid = s[:programs].zero? ? 0 : 100 * s[:valid] / s[:programs]
            kinds = @kinds.sort_by { |_, n| -n }.map { |k, n| "#{k} #{n}" }.join(" · ")
            "fuzz: #{s[:programs]} programs (#{valid}% valid), #{(s[:programs] / seconds).round(1)}/s; #{kinds}; " \
              "#{s[:new_buckets]} new bucket(s); coverage #{@store.coverage.size} lines"
          end
          @store.log(line)
          @out.puts(line)
        end
      end
    end
  end
end
