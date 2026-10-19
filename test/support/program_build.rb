# frozen_string_literal: true

require "rbconfig"
require_relative "program_run"
require_relative "binaries"
require_relative "progress"
require_relative "harness/runner"
require_relative "../../lib/zr/native/build"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/cli"

module Zr
  module Test
    # Builds a program test with zr and runs the binary (`ProgramRun` runs
    # ruby). A test below `cli/` builds with `zr build` in its own process,
    # as a user does, and so tests the command line and the link too. Any
    # other test builds in this process: a new ruby for each test would
    # load the whole compiler each time, and for a small program that load
    # is almost all of the cost.
    #
    # `answer` gives a `Harness::Answer`, or `[kind, why]` when zr does not
    # build or run the program: :refused (zr does not support a form),
    # :backend, :timeout, :build (the command line failed).
    module ProgramBuild
      # A refusal is not a defect: zr does not support the form.
      REFUSALS = [Zr::Refused].freeze

      # An unrescued stop at run time: the ruby report of a
      # NotImplementedError or LoadError, or a stop from the kernel.
      STOP = /^(?:zr: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/

      ROOT = File.expand_path("../..", __dir__)

      module_function

      # `parts` (a hash, or nil) gets the seconds of the lowering, the
      # link and the run (`Progress.clock`); a `zr build` counts as lowering.
      def answer(test, runner, parts = nil)
        target = runner.target
        ProgramRun.within(test) do |run, rb|
          bin = File.join(File.dirname(run), "p")
          built = cli?(test) ? Progress.clock(parts, :lower) { cli(test, run, bin, runner) } : in_process(test, run, bin, target, parts)
          next built if built

          command, env = runner.run(bin, test.args, cli?(test) && !runner.wasm? ? zr_run_env.merge(test.env) : test.env)
          megabytes = [test.limits[:run_mb] || 0, Harness::Child::RUN_MB].max
          out, = Progress.clock(parts, :run) do
            Harness::Child.run(command, cwd: run, stdin: test.stdin, env: env, seconds: Harness::Child::SECONDS, megabytes: megabytes)
          end
          verdict(Harness::Normalize.answer(out, rb, run), megabytes, runner)
        end
      end

      def cli?(test) = test.rel.start_with?("cli/")

      # What `zr run` gives the binary that it runs (CLI::Runner.program_env):
      # RbConfig.ruby is zr, and zr's ruby tree is its home. A test below
      # `cli/` runs as a user runs it.
      def zr_run_env
        { "ZR_RUBY" => CLI::Runner.pinned_launcher(CLI::Runner::EXE), "ZR_HOME" => CLI::Runner::HOME }
      end

      # Builds in this process. Returns nil, or `[kind, why]`.
      def in_process(test, run, bin, target, parts = nil)
        source = test.source
        kept = Binaries.path(target, test, source) if Binaries.wanted?(target)
        return nil if Binaries.take(kept, bin)

        program = Progress.clock(parts, :lower) { Dir.chdir(run) { lower(source, test.rel, target) } }
        return program if program.is_a?(Array)

        work = File.dirname(bin)
        why = Progress.clock(parts, :link) { target.link ? Native::Build.program(program, bin, work: work) : Native::Build.wasm_program(program, bin) }
        return [:backend, why] if why

        Binaries.keep(kept, bin, program, work)
        nil
      end

      # Builds with `zr build` in its own process, from the run directory.
      # A ZR_EVAL in the test's .env picks the back end of its eval support,
      # as it picks it for a user's build. Returns nil, or `[:build, why]`.
      def cli(test, run, bin, runner)
        megabytes = [test.limits[:build_mb] || 0, Harness::Child::BUILD_MB].max
        argv = runner.build_argv(test.rel, bin)
        out, = Harness::Child.run(argv, cwd: run, env: runner.build_env.merge(test.env.slice("ZR_EVAL")), seconds: Harness::Child::SECONDS * 5,
                                        megabytes: megabytes)
        return nil if out.code == 0

        tail = (out.stderr.empty? ? out.stdout : out.stderr).lines.last(20).join
        [:build, "`zr build` #{why(out, megabytes)}\n#{tail}"]
      end

      # Returns the program, or `[kind, why]` when zr does not build it.
      def lower(source, rel, target)
        compile(source, rel, target)
      rescue *REFUSALS => e
        # A form that ruby's compiler refuses ends as ruby's SyntaxError.
        (invalid = CLI::Refusals.invalid_program(rel, e)) ? compile(invalid, rel, target) : [:refused, e.message]
      rescue Backend::Refused => e
        [:backend, e.message]
      rescue SyntaxError => e
        # For a program that does not parse, ruby prints the parse's
        # warnings and a report, and exits 1. The binary does the same, as
        # `CLI::Commands::Compile#lower` builds it.
        warned = CLI::Refusals.syntax_warnings(rel, source, Hir::Switches::NONE)
        return [:refused, "a required file does not parse: #{e.message.lines.first.chomp}"] unless warned

        compile(CLI::Refusals.syntax_error_program(rel, e, warned), rel, target)
      end

      def compile(source, rel, target)
        if target.link
          Native::Build.lower(source, rel, BuildOptions.new(target: target))
        else
          Zr::Program.build(source, rel, BuildOptions.new(target: target))
        end
      end

      # The answer of the binary, or `[kind, why]` when it does not count.
      def verdict(answer, megabytes, runner, seconds: Harness::Child::SECONDS)
        return [:timeout, "ran past #{seconds}s"] if answer.code == :timeout
        return [:backend, "held more than #{megabytes} MB"] if answer.code == :memory
        return [:backend, "the module trapped:\n#{answer.stderr}"] if runner.trapped?(answer) && !answer.signal
        if (stop = answer.stderr.dup.force_encoding(Encoding::UTF_8).scrub[STOP, 1])
          return [:refused, "run time: #{stop}"]
        end

        answer
      end

      def why(out, megabytes)
        case out.code
        when :timeout then "ran past #{Harness::Child::SECONDS * 5}s"
        when :memory then "held more than #{megabytes} MB"
        else "exited #{out.code}"
        end
      end
    end
  end
end
