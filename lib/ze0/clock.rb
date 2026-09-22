# frozen_string_literal: true

module Ze0
  # `ZE0_TIMING=1` prints the seconds each phase of a build takes to
  # stderr, one line a phase, as it ends, and the collector's count
  # and its marking and sweeping milliseconds over the phase, which
  # ruby and a ze0 binary both report (GC.stat).
  def self.clock(label)
    return yield unless ENV["ZE0_TIMING"]

    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    before = collector
    yield
  ensure
    if began
      after = collector
      gc = after.zip(before).map { |a, b| a - b }
      warn format("ze0: %-40s %7.3fs  gc %d (%d major) mark %d ms sweep %d ms", label,
                  Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, *gc)
    end
  end

  # `[count, majors, marking ms, sweeping ms]` so far, zeros where the
  # collector does not say.
  def self.collector
    stat = GC.stat
    [stat[:count].to_i, stat[:major_gc_count].to_i, stat[:marking_time].to_i, stat[:sweeping_time].to_i]
  rescue StandardError
    [0, 0, 0, 0]
  end
end
