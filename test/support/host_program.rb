# frozen_string_literal: true

require_relative "program_run"
require_relative "program_build"
require_relative "harness/child"
require_relative "harness/clean_env"
require_relative "../../lib/zr/machine/host/walk"

module Zr
  module Test
    # Runs a program test on CRuby over zr's kernel (`bin/test programs
    # --host`, A7): no build. This process walks the core and the gem
    # prelude once (`walk`); each test runs in a fork of it, so it starts
    # from the same heap, with the test's directory, arguments,
    # environment and input. Its answer goes through the same
    # normalization and verdict as a binary's.
    module HostProgram
      # The walker runs the core's Ruby (Onig's regexp compiler, for one)
      # much slower than a binary: `require "date"` takes about 50 s. So a
      # test gets this many times a binary's time limit, which stays under
      # the worker's deadline (`Workers::DEADLINE`).
      SLOWER = 2

      module_function

      def limit = ProgramRun::LIMIT * SLOWER

      def walk
        @walk ||= Machine::Host::Walk.new.tap(&:prepare)
      end

      def answer(test, runner)
        w = walk
        ProgramRun.within(test) do |run, rb|
          megabytes = [test.limits[:run_mb] || 0, Harness::Child::RUN_MB].max
          out = forked(test, run, w, megabytes)
          ProgramBuild.verdict(Harness::Normalize.answer(out, rb, run), megabytes, runner, seconds: limit)
        end
      end

      # The answer of the program in a child of this process.
      def forked(test, run, w, megabytes)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_r, in_w = IO.pipe
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pid = Process.fork do
          Process.setpgid(0, 0)
          [out_r, err_r, in_w].each(&:close)
          $stdin.reopen(in_r)
          $stdout.reopen(out_w)
          $stderr.reopen(err_w)
          ENV.replace(Harness::CleanEnv.env(test.env))
          # The kernel and the core read some variables as they boot
          # (`RUBY_BOX`, `ZR_GC_STRESS`), so a test that sets any boots
          # again here, as a binary boots with its environment.
          w = Machine::Host::Walk.new.tap(&:prepare) unless test.env.empty?
          Dir.chdir(run)
          status = 1
          Thread.new do
            status = begin
              w.run(test.rel, test.args)
            rescue SyntaxError
              # As a binary does (`ProgramBuild.lower`): ruby's report, and
              # exit 1.
              report = CLI.syntax_report(test.rel) or raise
              w.run(test.rel, test.args, source: "$stderr.write(#{report.inspect})\nexit 1\n")
            end
          rescue Machine::Host::Walk::Unsupported => e
            $stderr.write("zr: #{e.message} is not implemented yet\n")
          end.join
          $stdout.flush
          $stderr.flush
          exit!(status)
        end
        [out_w, err_w, in_r].each(&:close)
        writer = Thread.new do
          in_w.binmode
          in_w.write(test.stdin) if test.stdin
        rescue Errno::EPIPE
          nil
        ensure
          in_w.close
        end
        reader = [out_r, err_r].map { |io| Thread.new { io.binmode.read } }
        status, over = Harness::Child.watch(pid, started + limit, megabytes)
        writer.join
        stdout, stderr = reader.map(&:value)
        return Harness::Answer.new(stdout, stderr, over, nil) if over

        Harness::Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig)
      end
    end
  end
end
