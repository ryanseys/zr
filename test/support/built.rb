# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/zr/zr"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/native/parallel"
require_relative "harness/wasmtime"

module Zr
  module Test
    # The runtime a check tier runs on: built ahead of time by
    # `rake build`, and only checked for by the tiers.
    #
    # The runtime object, the prelinked image and the eval road (for a
    # native target), or the module prelude (for wasm), are file caches
    # named by a digest of what made them, so the first build after an
    # edit under `lib` or `rt` writes them all again: twenty-five
    # megabytes of runtime, as much prelink, and seventy of compiler.
    # Alone on a quiet machine that is three minutes, and five more for
    # the wasm prelude and its road.
    #
    # A tier never pays it. The tiers once built the caches themselves
    # in the process that forks the workers, behind rules about which
    # runs were allowed to and which were not, and a run that started
    # cold had eight workers build the same runtime at once and report
    # timeouts that were not defects. Now a tier asks whether the caches
    # for its targets are there, and where one is not it stops at once
    # and names `rake build`. Building is one command, taken on purpose.
    #
    # What the tier does before it forks is load: the runtime's
    # description and symbol table, the prelinked image, the wasm
    # prelude. A worker is a fork of that process, so the eight of them
    # share one copy of all of it rather than reading and parsing it
    # each; `ForkPool#start` calls `Process.warmup` before the first
    # fork so what is shared stays shared past a worker's first
    # collection.
    module Built
      # A program that evals, so the eval road is built as well as the
      # runtime: nothing smaller reaches all three caches.
      EVALS = %(eval("1")\n)
      PLAIN = %(puts 1\n)

      module_function

      # The targets a run builds for: this host's, and wasm32-wasi where
      # wasmtime is installed and the run was given that target or asks
      # for it (the unit tier, whose files build modules). Another native
      # target is built by a `zr` of its own (`E2E.build`), with a
      # toolchain this process may not have, and is left to it.
      def targets(wasm: false)
        wasm ||= ENV["ZR_TARGET"] == Target::WASM32_WASI.triple
        [Target.default, *(Target::WASM32_WASI if wasm && Harness::Wasmtime.installed?)].uniq
      end

      # Stops the run where a target's caches are not built, else loads
      # them into this process for the workers to share. `ZR_BUILT=0`
      # asks for neither: for a file that builds no program -- the IR,
      # the encoders, the parsers -- while the runtime is being built
      # for something else. A file that does build then builds the
      # runtime for itself, cold, as `zr build` would.
      def ready!(wasm: false)
        return if ENV["ZR_BUILT"] == "0"

        targets(wasm: wasm).each do |target|
          abort("zr is not built for #{target.triple}: run `rake build` first") unless built?(target)
          load(target)
        end
      end

      # Whether `target`'s caches are there: a build leaves a mark under
      # the runtime's digest once the last of them is written. The
      # runtime object alone would not do -- the prelink and the road
      # follow it by minutes, and a tier that started between the two
      # ran a road half written.
      def built?(target) = File.exist?(mark(target))

      def mark(target) = File.join(Zr.cache, "built-#{Zr.runtime(target).digest}.ok")

      # The caches of `target`, read into this process once.
      def load(target)
        runtime = Zr.runtime(target)
        runtime.description
        return Native::Build.prelink([Native::Build.runtime_object(runtime)]) if target.link

        Native::Build.wasm_prelude(runtime, Native::Build.pending_for(Zr.program(PLAIN, "built.rb", target: target)))
      end

      # Builds every cache of each of `targets`, and says how long each
      # took. The targets build at once, each in a child of its own
      # with half the jobs, where the machine has the memory for two
      # builds (12 GB: a build holds three to four); else one after
      # another. Two at once on the M2 Pro: 5 minutes, not 7.5.
      def build(targets, say: $stderr)
        at_once = targets.size > 1 && Native::Parallel.machine_bytes >= 12 * (1 << 30)
        jobs = at_once ? [Native::Build.jobs / 2, 1].max : Native::Build.jobs
        statuses = if at_once
                     targets.map { |target| start(target, jobs: jobs, say: say) }.map { |pid| Process.wait2(pid).last }
                   else
                     targets.map { |target| Process.wait2(start(target, jobs: jobs, say: say)).last }
                   end
        failed = statuses.count { |status| !status.success? }
        abort("#{failed} of #{targets.size} builds did not finish") unless failed.zero?
      end

      # A child that builds `target`'s caches, and its pid. `ZR_JOBS` is
      # how a build is told its workers, and the child is the build's
      # alone.
      def start(target, jobs:, say:)
        say&.puts("building zr for #{target.triple}: the runtime, its image and the eval road")
        Process.fork do
          ENV["ZR_JOBS"] = jobs.to_s
          began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          target.link ? build_binary(target) : build_module(target)
          say&.puts(format("built zr for %s in %.1f s", target.triple, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began))
        end
      end

      def build_binary(target)
        program = Zr.program(EVALS, "built.rb", target: target)
        Dir.mktmpdir("zr-build-") do |work|
          why = Native::Build.program(program, File.join(work, "built"), work: work)
          raise "the build did not finish: #{why}" if why
        end
        Zr.write_cache(mark(target), "")
      end

      # A module with no linker: a plain program and one that evals, since
      # each waits on symbols of its own and so reads a prelude of its own.
      def build_module(target)
        Dir.mktmpdir("zr-build-") do |work|
          [PLAIN, EVALS].each_with_index do |source, i|
            program = Zr.program(source, "built.rb", target: target)
            why = Native::Build.wasm_program(program, File.join(work, "built#{i}.wasm"))
            raise "the build did not finish: #{why}" if why
          end
        end
        Zr.write_cache(mark(target), "")
      end
    end
  end
end
