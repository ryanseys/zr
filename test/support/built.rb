# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"
require_relative "harness/wasmtime"

module Ze0
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
      # target is built by a `ze0` of its own (`E2E.build`), with a
      # toolchain this process may not have, and is left to it.
      def targets(wasm: false)
        wasm ||= ENV["ZE0_TARGET"] == Target::WASM32_WASI.triple
        [Target.default, *(Target::WASM32_WASI if wasm && Harness::Wasmtime.installed?)].uniq
      end

      # Stops the run where a target's caches are not built, else loads
      # them into this process for the workers to share.
      def ready!(wasm: false)
        targets(wasm: wasm).each do |target|
          abort("ze0 is not built for #{target.triple}: run `rake build` first") unless built?(target)
          load(target)
        end
      end

      # Whether `target`'s caches are there. A native target's runtime
      # object names them all: the prelink and the road follow it. A wasm
      # target has no object -- its runtime is a prelude named after the
      # symbols a program waits on, which only a build can say -- so a
      # build leaves a mark under the runtime's digest instead.
      def built?(target) = File.exist?(mark(target))

      def mark(target)
        name = target.link ? "rt-#{Zr.runtime(target).digest}.o" : "built-#{Zr.runtime(target).digest}.ok"
        File.join(Zr.cache, name)
      end

      # The caches of `target`, read into this process once.
      def load(target)
        runtime = Zr.runtime(target)
        runtime.description
        return Native::Build.prelink([Native::Build.runtime_object(runtime)]) if target.link

        Native::Build.wasm_prelude(runtime, Native::Build.pending_for(Zr.program(PLAIN, "built.rb", target: target)))
      end

      # Builds every cache of each of `targets`, and says how long it took.
      def build(targets, say: $stderr)
        targets.each do |target|
          say&.puts("building ze0 for #{target.triple}: the runtime, its image and the eval road")
          began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          target.link ? build_binary(target) : build_module(target)
          say&.puts(format("built in %.1f s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began))
        end
      end

      def build_binary(target)
        program = Zr.program(EVALS, "built.rb", target: target)
        Dir.mktmpdir("ze0-build-") do |work|
          why = Native::Build.program(program, File.join(work, "built"), work: work)
          raise "the build did not finish: #{why}" if why
        end
      end

      # A module with no linker: a plain program and one that evals, since
      # each waits on symbols of its own and so reads a prelude of its own.
      def build_module(target)
        Dir.mktmpdir("ze0-build-") do |work|
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
