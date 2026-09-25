# frozen_string_literal: true

require_relative "config"

module Zr
  # With `ZR_TIMING=1`, each build phase prints one line to stderr when it
  # ends. The line gives the seconds, the collector's run count, and its
  # marking and sweeping milliseconds for the phase. Both ruby and a zr
  # binary report these (GC.stat).
  def self.clock(label)
    return yield unless Config.current.timing?

    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    before = collector
    yield
  ensure
    if began
      after = collector
      gc = after.zip(before).map { |a, b| a - b }
      warn format("zr: %-40s %7.3fs  gc %d (%d major) mark %d ms sweep %d ms", label,
                  Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, *gc)
    end
  end

  # `[count, majors, marking ms, sweeping ms]` so far, zeros where the
  # collector does not say. A collector that does not know a key raises;
  # the line is for a person, so it shows zeros and the build continues.
  def self.collector
    # Read one key at a time. A zr binary returns each counter at once,
    # but the full table walks the heap for its slot counts.
    %i[count major_gc_count marking_time sweeping_time].map { |key| GC.stat(key).to_i }
  rescue StandardError
    [0, 0, 0, 0]
  end
end
