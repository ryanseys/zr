# frozen_string_literal: true

module Ze0
  # `ZE0_TIMING=1` prints the seconds each phase of a build takes to
  # stderr, one line a phase, as it ends.
  def self.clock(label)
    return yield unless ENV["ZE0_TIMING"]

    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    warn format("ze0: %-40s %7.3fs", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) if began
  end
end
