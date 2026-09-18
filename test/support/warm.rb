# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

module Ze0
  module Test
    # The runtime object, the prelink and the eval road, built once
    # before a tier forks.
    #
    # Those three are file caches named by a digest of what made them, so
    # the first build after any edit under `lib` or `rt` writes all of
    # them again: twenty-five megabytes of runtime, as much prelink, and
    # forty-four of compiler. Alone on a quiet machine that is 88 s.
    #
    # A tier that starts cold does not pay it once, though. Every worker
    # builds the same three files at the same time, each one already
    # forking six of its own, and on a twelve-core machine none of them
    # finishes inside `ForkPool::DEADLINE`: on 2026-09-18 four correct
    # examples were reported as four timeouts, twice over. Built here, in
    # the process that forks the workers, it happens once, nothing is
    # waiting on it, and the workers inherit it.
    module Warm
      # A program that evals, so the eval road is made as well as the
      # runtime: nothing smaller reaches all three caches.
      SOURCE = %(eval("1")\n)

      # Builds the caches, and answers how long it took, or nil where it
      # did nothing. It costs about a second once they are there.
      #
      # `cold: false` asks for no more than that second: where the caches
      # are missing it does nothing at all, which is what a narrow run of
      # checks that build no program wants -- those are the compiler's
      # own Ruby, and twelve minutes before them would be a surprise.
      # `ZE0_WARM=0` leaves them alone whatever is asked.
      def self.call(target: Target.default, cold: true, say: $stderr)
        return if ENV["ZE0_WARM"] == "0"
        return unless cold || warm?(target)

        freezing = !warm?(target)
        say&.puts("warming #{target.triple}: the runtime is cold, and this takes minutes") if freezing
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        build(target)
        spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began
        say&.puts(format("warmed in %.1f s", spent)) if freezing
        spent
      end

      # Whether the runtime's object is already made. The prelink and the
      # road follow it, so this one file answers for all three.
      def self.warm?(target) = File.exist?(File.join(Zr::CACHE, "rt-#{Zr.runtime(target).digest}.o"))

      def self.build(target)
        program = Zr.program(SOURCE, "warm.rb", target: target)
        Dir.mktmpdir("ze0-warm-") do |work|
          why = Native::Build.program(program, File.join(work, "warm"), work: work)
          raise "the warm-up did not build: #{why}" if why
        end
      end
    end
  end
end
