# frozen_string_literal: true

require "rbconfig"
require_relative "program_run"
require_relative "binaries"
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

      def answer(test, runner)
        target = runner.target
        ProgramRun.within(test) do |run, rb|
          bin = File.join(File.dirname(run), "p")
          built = cli?(test) ? cli(test, run, bin, runner) : in_process(test, run, bin, target)
          next built if built

          command, env = runner.run(bin, test.args, test.env)
          megabytes = [test.limits[:run_mb] || 0, Harness::Child::RUN_MB].max
          out, = Harness::Child.run(command, cwd: run, stdin: test.stdin, env: env, seconds: ProgramRun::LIMIT,
                                             megabytes: megabytes)
          verdict(Harness::Normalize.answer(out, rb, run), megabytes, runner)
        end
      end

      def cli?(test) = test.rel.start_with?("cli/")

      # Builds in this process. Returns nil, or `[kind, why]`.
      def in_process(test, run, bin, target)
        source = test.source
        files = test.files ? file_parts(test.files) : {}
        kept = Binaries.path(target, source, test.rel, files) if Binaries.wanted?(target)
        return nil if Binaries.take(kept, bin)

        program = Dir.chdir(run) { lower(source, test.rel, target) }
        return program if program.is_a?(Array)

        work = File.dirname(bin)
        why = target.link ? Native::Build.program(program, bin, work: work) : Native::Build.wasm_program(program, bin)
        return [:backend, why] if why

        Binaries.keep(kept, bin, program, work)
        nil
      end

      # The files of a test for the key of a kept binary: each name with
      # its bytes, and a symbolic link by its target.
      def file_parts(dir)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort.filter_map do |name|
          path = File.join(dir, name)
          next if File.basename(name) == "." || (File.directory?(path) && !File.symlink?(path))

          [name, File.symlink?(path) ? { symlink: File.readlink(path) } : File.binread(path)]
        end.to_h
      end

      # Builds with `zr build` in its own process, from the run directory.
      # Returns nil, or `[:build, why]`.
      def cli(test, run, bin, runner)
        megabytes = [test.limits[:build_mb] || 0, Harness::Child::BUILD_MB].max
        argv = runner.build_argv(test.rel, bin)
        out, = Harness::Child.run(argv, cwd: run, env: runner.build_env, seconds: ProgramRun::LIMIT * 5,
                                        megabytes: megabytes)
        return nil if out.code == 0

        tail = (out.stderr.empty? ? out.stdout : out.stderr).lines.last(20).join
        [:build, "`zr build` #{why(out, megabytes)}\n#{tail}"]
      end

      # Returns the program, or `[kind, why]` when zr does not build it.
      def lower(source, rel, target)
        compile(source, rel, target)
      rescue *REFUSALS => e
        [:refused, e.message]
      rescue Backend::Refused => e
        [:backend, e.message]
      rescue SyntaxError => e
        # For a program that does not parse, ruby prints a report and
        # exits 1. The binary does the same, with the ruby report.
        # `Zr::CLI.lower` does the same, and the two must stay the same.
        report = CLI.syntax_report(rel)
        return [:refused, "a required file does not parse: #{e.message.lines.first.chomp}"] unless report

        compile("$stderr.write(#{report.inspect})\nexit 1\n", rel, target)
      end

      def compile(source, rel, target)
        target.link ? Native::Build.lower(source, rel, target: target) : Zr.program(source, rel, target: target)
      end

      # The answer of the binary, or `[kind, why]` when it does not count.
      def verdict(answer, megabytes, runner)
        return [:timeout, "ran past #{ProgramRun::LIMIT}s"] if answer.code == :timeout
        return [:backend, "held more than #{megabytes} MB"] if answer.code == :memory
        return [:backend, "the module trapped:\n#{answer.stderr}"] if runner.trapped?(answer) && !answer.signal
        if (stop = answer.stderr.dup.force_encoding(Encoding::UTF_8).scrub[STOP, 1])
          return [:refused, "run time: #{stop}"]
        end

        answer
      end

      def why(out, megabytes)
        case out.code
        when :timeout then "ran past #{ProgramRun::LIMIT * 5}s"
        when :memory then "held more than #{megabytes} MB"
        else "exited #{out.code}"
        end
      end
    end
  end
end
