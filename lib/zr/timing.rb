# frozen_string_literal: true

require_relative "config"
require_relative "session"

module Zr
  # With `ZR_TIMING=1`, each build phase prints a line to stderr when it
  # starts ("zr: inlining the unit ..."), so a long phase shows what it
  # does, and one when it ends. The end line gives the seconds, the
  # collector's run count, and its marking and sweeping milliseconds for
  # the phase. Both ruby and a zr binary report these (GC.stat).
  module Timing
    module_function

    # Seconds on the monotonic clock, for a difference of two reads.
    #: () -> Float
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Runs the block and returns its value. `doing` names the phase as it
    # starts, and `label` as it ends; `zr-dev compile` keys its rows by
    # the label.
    #: [T] (String doing, String label) { () -> T } -> T
    def phase(doing, label)
      return yield unless Config.current.timing?

      warn "zr: #{doing} ..."
      began = now
      before = collector
      begin
        yield
      ensure
        after = collector
        gc = after.each_with_index.map { |a, i| a - before.fetch(i) }
        warn format("zr: %-40s %7.3fs  gc %d (%d major) mark %d ms sweep %d ms", label,
                    now - began, *gc)
      end
    end

    # `[count, majors, marking ms, sweeping ms]` so far, zeros where the
    # collector does not say. A collector that does not know a key raises;
    # the line is for a person, so it shows zeros and the build continues.
    #: () -> Array[Integer]
    def collector
      # Read one key at a time. A zr binary returns each counter at once,
      # but the full table walks the heap for its slot counts.
      %i[count major_gc_count marking_time sweeping_time].map { |key| GC.stat(key).to_i }
    rescue StandardError
      [0, 0, 0, 0]
    end

    # Runs the block and returns its value. With timing on, its seconds
    # add to the tally of `part`: a part that runs many times, such as a
    # pass over each function, then shows its sum (`report`).
    #: [T] (Module | String part) { () -> T } -> T
    def tally(part)
      return yield unless Config.current.timing?

      began = now
      begin
        yield
      ensure
        tallies[part] += now - began
      end
    end

    # `{ part => seconds }` of this process since the last `report`. A
    # forked worker sends its own to the parent, which adds them (`add`).
    #: () -> Hash[Module | String, Float]
    def tallies = Session.current.memo(:timing_tallies) { Hash.new(0.0) }

    #: (Hash[Module | String, Float] more) -> void
    def add(more)
      sums = tallies
      more.each { |part, seconds| sums[part] += seconds }
    end

    # Prints each tally, the largest first, with its share of `total`
    # seconds, and clears them. A part may hold another (emit holds its
    # locals), so the shares need not sum to 100%.
    #: (String title, Float total) -> void
    def report(title, total)
      sums = tallies
      return if sums.empty? || !total.positive?

      warn "zr: #{title}"
      sums.sort_by { |_, seconds| -seconds }.each do |part, seconds|
        name = part.is_a?(Module) ? part.name.to_s[/\w+\z/] : part
        warn format("zr:   %-24s %9.2fs %5.1f%%", name, seconds, 100 * seconds / total)
      end
      sums.clear
    end
  end
end
