# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/zr/zr"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/native/parallel"
require_relative "harness/wasmtime"

module Zr
  module Test
    # The runtime that the tests run on, built by `rake build`.
    #
    # For a native target the build makes the runtime object, the
    # prelinked runtime image and the eval support object. For wasm it
    # makes the module prelude. Each is a file in the cache, named by a
    # digest of its sources. After a change under `lib` or `rt`, the next
    # build makes them again: about three minutes, and five more for wasm.
    #
    # `ready!` builds what is missing before the tier forks its workers.
    # (If each worker built it, eight builds ran at once and timed out.)
    # Then it loads the caches, so that all workers share one copy.
    module Built
      # A program that calls eval, so that the build also makes the eval
      # support object.
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

      # Builds the caches of each target that has none, then loads them
      # into this process for the workers to share. `ZR_BUILT=0` skips
      # both, for a test file that builds no program.
      def ready!(wasm: false)
        return if ENV["ZR_BUILT"] == "0"

        build(targets(wasm: wasm))
        targets(wasm: wasm).each { |target| load(target) }
      end

      # Whether the caches of `target` are complete. A build writes the
      # mark file last, after every cache file is written.
      def built?(target) = File.exist?(mark(target))

      def mark(target) = File.join(Zr.cache, "built-#{Zr.runtime(target).digest}.ok")

      # The caches of `target`, read into this process once.
      def load(target)
        runtime = Zr.runtime(target)
        runtime.description
        return Native::Build.prelink([Native::Build.runtime_object(runtime)]) if target.link

        Native::Build.wasm_prelude(runtime, Native::Build.pending_for(Zr.program(PLAIN, "built.rb", target: target)))
      end

      # Builds the caches of each of `targets` that are not current, and
      # says how long each build took. When the machine has the memory
      # for two builds (12 GB), the targets build at the same time, each
      # in its own child process with half the jobs.
      def build(targets, say: $stderr)
        current, targets = targets.partition { |target| built?(target) }
        current.each { |target| say&.puts("zr runtime for #{target.triple} is up to date (cache: #{cache_dir})") }
        return if targets.empty?

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

      # Starts a child process that builds the caches of `target`, and
      # returns its pid. `ZR_JOBS` gives the child its number of workers.
      def start(target, jobs:, say:)
        say&.puts("building the zr runtime for #{target.triple} (a few minutes after a change under lib/ or rt/)")
        Process.fork do
          ENV["ZR_JOBS"] = jobs.to_s
          began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          target.link ? build_binary(target) : build_module(target)
          say&.puts(format("built the zr runtime for %s in %.1f s (cache: %s)",
                           target.triple, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, cache_dir))
        end
      end

      # The cache directory, relative to the working directory when it
      # is below it.
      def cache_dir
        dir = Zr.cache
        dir.start_with?(File.join(Dir.pwd, "")) ? dir.delete_prefix(File.join(Dir.pwd, "")) : dir
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
