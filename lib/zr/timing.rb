# frozen_string_literal: true

require_relative "config"

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
  end
end
