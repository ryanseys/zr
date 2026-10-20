# frozen_string_literal: true

require_relative "config"
require_relative "session"

module Zr
  # One line on a terminal that names the build phase that runs now, so
  # the first build of the runtime (some minutes) shows that it moves.
  # `Runtime.announce` starts it; `Timing.phase` runs each phase through
  # it. The line is there only while a phase runs: the phase's end erases
  # it, so a later warning starts on a clean line. A forked worker shows
  # nothing. `--quiet`, `ZR_TIMING`, `TERM=dumb` or a stderr that is not
  # a terminal turn it off. It prints no color.
  module Notice
    module_function

    # Shows the phases from now on, in this process.
    #: () -> void
    def start
      return unless $stderr.tty? && ENV["TERM"] != "dumb"

      config = Config.current
      return if config.quiet? || config.timing?

      Session.current.set(:notice, [Process.clock_gettime(Process::CLOCK_MONOTONIC), Process.pid])
    end

    # Runs the block as the phase `doing`, and returns its value.
    #: [T] (String doing) { () -> T } -> T
    def phase(doing)
      return yield unless active?

      phases << doing
      show
      begin
        yield
      ensure
        phases.pop
        phases.empty? ? erase : show
      end
    end

    #: () -> bool
    def active?
      began = Session.current.memo(:notice) { nil } #: [Float, Integer]?
      !began.nil? && began.last == Process.pid
    end

    #: () -> Array[String]
    def phases = Session.current.memo(:notice_phases) { [] }

    #: () -> void
    def show
      began, = Session.current.memo(:notice) { [0.0, 0] } #: [Float, Integer]
      seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - began).round
      $stderr.print "\r\e[Kzr: #{phases.last} (#{seconds} s)"
      $stderr.flush
    end

    #: () -> void
    def erase
      $stderr.print "\r\e[K"
      $stderr.flush
    end
  end
end
