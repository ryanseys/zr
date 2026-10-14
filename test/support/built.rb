# frozen_string_literal: true

require_relative "flag"
require "fileutils"
require "tmpdir"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/native/parallel"
require_relative "harness/selected_target"
require_relative "harness/wasmtime"
require_relative "needs"

module Zr
  module Test
    # The runtime that the tests run on, built by `rake build`.
    #
    # For a native target the build makes the runtime object, the
    # prelinked runtime image and, when a test needs it, the eval support
    # object. For wasm it
    # makes two module preludes, without and with eval support. Each is a file in the cache, named by a
    # digest of its sources. After a change under `lib` or `runtime`, the next
    # build makes them again: about three minutes, and five more for wasm.
    #
    # `ready!` builds what is missing before the run forks its workers.
    # If each worker built it, eight builds would run at once and time out.
    # Then it loads the caches, so that all workers share one copy. It runs
    # as a minitest plugin (test_helper.rb), after the run has loaded its
    # test files.
    module Built
      ROOT = File.expand_path("..", __dir__)
      # The mark of a whole build is an empty entry of the store kind `built`.
      Zr::Cache::Store.register(Zr::Cache::Store::Kind.new(:built, :raw, "", nil))

      # The unit test files that this run loaded: each declares what it
      # needs (`Needs`). The program tests get theirs from ProgramsTest.
      def self.minitest_plugin_init(_options)
        files = $LOADED_FEATURES.select { |path| path.start_with?(File.join(ROOT, "")) && path.end_with?("_test.rb") }
        ready!(files: files - [File.join(ROOT, "programs_test.rb")])
      end

      # A program that calls eval, so that the build also makes the eval
      # support object.
      EVALS = %(eval("1")\n)
      PLAIN = %(puts 1\n)

      module_function

      # Returns the targets that a run builds for: the host, and also
      # wasm32-wasi when wasmtime is installed and the run selects that
      # target or `wasm` is true (the unit tier builds WASI modules). It
      # builds no other native target.
      def targets(wasm: false)
        wasm ||= Harness.selected_target == Target::WASM32_WASI
        [Target.default, *(Target::WASM32_WASI if wasm && Harness::Wasmtime.installed?)].uniq
      end

      # Builds the caches of each target that has none, then loads them
      # into this process for the workers to share. `ZR_TEST_BUILT=0` skips
      # both.
      #
      # `files` are the unit test files of the run. Each declares what it
      # needs (`Needs`); a run of files that build no program builds and
      # loads nothing. Eval support takes minutes to build after an edit, so
      # it is built only when a file declares `eval`. Nil means that the run
      # is not known.
      def ready!(wasm: false, files: nil)
        return unless Zr::Test.flag?("ZR_TEST_BUILT", default: true)

        need = files ? Needs.most(files) : :eval
        return if need == :none

        build(targets(wasm: wasm), evals: need == :eval)
        targets(wasm: wasm).each { |target| load(target) }
      end

      # `ready!` for a run of program tests (`Case`s): they need the
      # runtime, and eval support when one of their programs evals.
      def ready_for_programs!(tests, wasm: false)
        return unless Zr::Test.flag?("ZR_TEST_BUILT", default: true)
        return if tests.empty?

        build(targets(wasm: wasm), evals: programs_eval?(tests))
        targets(wasm: wasm).each { |target| load(target) }
      end

      # The most programs that `programs_eval?` reads. Each costs a HIR
      # build, so a larger run builds eval support without reading them.
      PROGRAMS_READ = 400

      # Whether one of `tests` evals (`Hir::Program#evals`, the flag that
      # makes a build link eval support), where its files are, as the run
      # writes them. An error in the check means yes. A worker that meets
      # an eval program without eval support builds it, which is slow but
      # correct.
      def programs_eval?(tests)
        return true if tests.size > PROGRAMS_READ

        require_relative "program_run"
        tests.any? do |test|
          ProgramRun.within(test) { |run, _| Dir.chdir(run) { Zr::Hir.build(test.source, test.rel).evals } }
        end
      rescue StandardError, ScriptError
        true
      end

      # Whether the caches of `target` are complete: its mark, which a build
      # writes last, is in the store, and so is its runtime object. A build
      # with eval support also serves a run that does not need it.
      def built?(target, evals: true)
        return false if target.link && !File.exist?(Runtime.for(target).object_path)

        [true, *(false unless evals)].any? { |full| Zr::Cache::Store.read(:built, mark(target, evals: full)) }
      end

      # The store key of the mark of a build of `target`.
      def mark(target, evals: true) = "#{Runtime.for(target).digest}#{"-plain" unless evals}"

      # Writes the mark of a whole build of `target`, after every cache file
      # of the build. The target's root names only its newest mark, so an
      # eviction or a clean takes the older ones.
      def finish(target, evals:)
        file = Zr::Cache::Store.write(:built, mark(target, evals: evals), "")
        Zr::Cache::Store.root("#{target.triple}-built#{"-plain" unless evals}", [file])
      end

      # Reads the caches of `target` into this process one time.
      def load(target)
        runtime = Runtime.for(target)
        runtime.description
        # Only a Mach-O link has a prelink to keep; an ELF one links the
        # runtime object with the target's cc.
        return Native::Build.prelink([Native::Build.runtime_object(runtime)]) if target.link && target.object_format == :macho
        return Native::Build.runtime_object(runtime) if target.link

        Native::Build.wasm_prelude(runtime, Native::Build.pending_for(Program.build(PLAIN, "built.rb", BuildOptions.new(target: target))))
      end

      # Builds the caches of each target in `targets` that is not current,
      # and prints the time of each build. When the machine has the memory
      # for two builds (12 GB), the targets build at the same time. Each
      # build is a child process with half the jobs.
      def build(targets, say: $stderr, evals: true)
        current, targets = targets.partition { |target| built?(target, evals: evals) }
        current.each { |target| say&.puts("zr runtime for #{target.triple} is up to date (cache: #{cache_dir})") }
        return if targets.empty?

        at_once = targets.size > 1 && Native::Parallel.machine_bytes >= 12 * (1 << 30)
        jobs = at_once ? [Native::Build.jobs / 2, 1].max : Native::Build.jobs
        statuses = if at_once
                     targets.map { |target| start(target, jobs: jobs, say: say, evals: evals) }.map { |pid| Process.wait2(pid).last }
                   else
                     targets.map { |target| Process.wait2(start(target, jobs: jobs, say: say, evals: evals)).last }
                   end
        failed = statuses.count { |status| !status.success? }
        abort("#{failed} of #{targets.size} builds did not finish") unless failed.zero?
      end

      # Starts a child process that builds the caches of `target`, and
      # returns its pid. `ZR_JOBS` gives the child its number of workers.
      def start(target, jobs:, say:, evals: true)
        say&.puts("building the zr runtime#{" and eval support" if evals} for #{target.triple} " \
                  "(#{evals ? "a few minutes" : "about half a minute"} after a change under lib/)")
        Process.fork do
          ENV["ZR_JOBS"] = jobs.to_s
          Config.reset!
          began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          target.link ? build_binary(target, evals: evals) : build_module(target)
          say&.puts(format("built the zr runtime for %s in %.1f s (cache: %s)",
                           target.triple, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, cache_dir))
        end
      end

      # The cache directory, relative to the working directory when it
      # is below it.
      def cache_dir
        dir = Zr::Paths.cache
        dir.start_with?(File.join(Dir.pwd, "")) ? dir.delete_prefix(File.join(Dir.pwd, "")) : dir
      end

      # `Native::Build.lower` writes the runtime object and releases the
      # runtime's IR before it lowers eval support, so the two are not in
      # memory together. Less memory in this process gives more workers
      # to the eval support build (`Native::Parallel.afforded`).
      def build_binary(target, evals: true)
        program = Native::Build.lower(evals ? EVALS : PLAIN, "built.rb", BuildOptions.new(target: target))
        Dir.mktmpdir("zr-build-") do |work|
          why = Native::Build.program(program, File.join(work, "built"), work: work)
          raise "the build did not finish: #{why}" if why
        end
        finish(target, evals: evals)
      end

      # A WASI module has no linker. Build a plain program and a program
      # that evals, because each uses a different prelude: the second
      # prelude also contains eval support.
      def build_module(target)
        Dir.mktmpdir("zr-build-") do |work|
          [PLAIN, EVALS].each_with_index do |source, i|
            program = Program.build(source, "built.rb", BuildOptions.new(target: target))
            why = Native::Build.wasm_program(program, File.join(work, "built#{i}.wasm"))
            raise "the build did not finish: #{why}" if why
          end
        end
        finish(target, evals: true)
      end
    end
  end
end
