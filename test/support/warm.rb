# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"
require_relative "harness/wasmtime"

module Ze0
  module Test
    # The runtime object, the prelink and the eval road, built once in
    # the tier's own process before it forks its first worker.
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
    #
    # They inherit more than the files. The process that builds them is
    # left holding what it read to do so -- the runtime's description,
    # its symbol table, the prelinked image and the parse of every file
    # under `rt` -- and a worker is a fork of that process, so the eight
    # of them share one copy of all of it. That is why this is called
    # here and not in a ruby of its own: warmed next door, the caches
    # would be on disk and each worker would read and parse them again.
    # `ForkPool#start` calls `Process.warmup` before the first fork, so
    # what is shared stays shared past a worker's first collection.
    module Warm
      # A program that evals, so the eval road is made as well as the
      # runtime: nothing smaller reaches all three caches.
      SOURCE = %(eval("1")\n)

      # What a unit test names when it builds a program or lowers the
      # runtime. A file under `test/unit` that names none of these is
      # the compiler's own Ruby and builds nothing (`light?`).
      BUILDS = /Native::Build|Zr\.(?:program|runtime|core)|Zr::Runtime|Machine\.unit|RtPrograms|OnigJIT|Obj::JIT/

      # Whether a run of `paths` alone can leave a cold cache cold: every
      # one is a unit test that builds nothing. A directory, a spec, an
      # end-to-end program and a unit test that builds all warm first --
      # left cold, each of eight workers builds the same runtime at once,
      # each forking six of its own, and none of them ends inside its
      # deadline: `rake test test/unit/programs_test.rb` once ran past
      # twelve minutes that way and reported timeouts that were not
      # defects.
      def self.light?(paths)
        paths.all? { |path| unit_test?(path) && !File.read(path).match?(BUILDS) }
      end

      def self.unit_test?(path) = File.file?(path) && File.dirname(path) == File.expand_path("../unit", __dir__)

      # The targets a run builds for, so the ones to warm: this host's,
      # and wasm32-wasi beside it where the run was given that target or
      # is of unit tests, which build modules for wasmtime. Another
      # native target is built by a `ze0` of its own (`E2E.build`), with
      # a toolchain this process may not have, and is left to it.
      def self.targets(wasm: false)
        wasm ||= ENV["ZE0_TARGET"] == Target::WASM32_WASI.triple
        [Target.default, *(Target::WASM32_WASI if wasm && wasmtime?)].uniq
      end

      def self.wasmtime? = Harness::Wasmtime.installed?

      # `call` for each of `targets`; the seconds all of it took.
      def self.all(targets, cold: true, say: $stderr)
        targets.sum { |target| call(target: target, cold: cold, say: say).to_f }
      end

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
      # road follow it, so this one file answers for all three. A wasm
      # target has no object: its runtime is a prelude named after the
      # symbols a program waits on, which only a build can say, so the
      # last warm-up leaves a mark under the runtime's digest instead.
      def self.warm?(target) = File.exist?(mark(target))

      def self.mark(target)
        name = target.link ? "rt-#{Zr.runtime(target).digest}.o" : "warm-#{Zr.runtime(target).digest}.ok"
        File.join(Zr.cache, name)
      end

      def self.build(target)
        return build_module(target) unless target.link

        program = Zr.program(SOURCE, "warm.rb", target: target)
        Dir.mktmpdir("ze0-warm-") do |work|
          why = Native::Build.program(program, File.join(work, "warm"), work: work)
          raise "the warm-up did not build: #{why}" if why
        end
      end

      # A module with no linker: a plain program and one that evals, since
      # each waits on symbols of its own and so reads a prelude of its own.
      def self.build_module(target)
        Dir.mktmpdir("ze0-warm-") do |work|
          [%(puts 1\n), SOURCE].each_with_index do |source, i|
            program = Zr.program(source, "warm.rb", target: target)
            why = Native::Build.wasm_program(program, File.join(work, "warm#{i}.wasm"))
            raise "the warm-up did not build: #{why}" if why
          end
        end
        Zr.write_cache(mark(target), "")
      end
    end
  end
end
