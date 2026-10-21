# frozen_string_literal: true

require_relative "baseline"
require_relative "harness/requirements"
require_relative "harness/selected_target"
require_relative "program_build"
require_relative "program_selection"

module Zr
  module Test
    # The program tests (test/programs_test.rb). Each test is a plain Ruby
    # file with ruby's output next to it (`Case`). zr builds it, runs the
    # binary, and compares stdout, stderr and the exit status with ruby's,
    # byte for byte. With `host`, each program runs on CRuby over the
    # kernel (`HostProgram`), and not as a binary.
    #
    # `check` gives the outcome of one test: :pass, :fail (the output is
    # different), :error (zr does not build or run it), or :skip (this
    # machine cannot run it, or the baseline allows its failure).
    class Programs
      attr_reader :runner

      def initialize(target: Harness.selected_target, host: false, allowed: host ? Baseline.host : Baseline.for(target))
        @runner = Harness::Runner.new(ProgramBuild::ROOT, target)
        @allowed = allowed
        @host = host
      end

      def host? = @host

      # Why the baseline allows `test` to fail, or nil. A baseline names
      # only programs below test/programs.
      def baseline(test) = test.root == ProgramSelection::ROOT ? @allowed[test.rel] : nil

      # `[kind, detail]` for one test. `parts` (a hash, or nil) gets the
      # seconds of each part of its build (`ProgramBuild.answer`).
      def check(test, parts: nil)
        kind, detail = unmet(test) ? [:skip, unmet(test)] : outcome(test, parts: parts)
        baseline(test) ? baselined(test, kind, detail) : [kind, detail]
      end

      # Why this machine cannot run `test`, or nil.
      def unmet(test)
        return @runner.refusal if @runner.refusal

        platforms, needs = test.needs.partition { |name| Harness::Runner::PLATFORMS.value?(name) || name.start_with?("linux-") }
        here = [@runner.platform, @runner.recording]
        return "runs only on #{platforms.join(", ")}" unless platforms.empty? || platforms.intersect?(here)

        need = needs.find { |name| !Harness::Requirements.met?(name, @runner) }
        "needs #{need}" if need
      end

      def outcome(test, mode: ProgramSelection.mode, parts: nil)
        want = expected(test, mode)
        return want if want.is_a?(Array)

        got = @host ? HostProgram.answer(test, @runner) : ProgramBuild.answer(test, @runner, parts)
        return [:error, got.join(": ")] if got.is_a?(Array)

        same = %i[stdout stderr code signal].all? { |part| want.public_send(part) == got.public_send(part) }
        same ? [:pass, nil] : [:fail, want.diff(got)]
      end

      # The answer that `test` expects in `mode` (`MODES`), or `[:error,
      # why]` when it has none.
      def expected(test, mode)
        case mode
        when :live then live(test)
        when :record
          written = record(test)
          return [:error, "zr-dev expect: #{written}"] if written&.start_with?("ruby did not finish")

          ProgramRun.expected(test, @runner.recordings)
        else
          return ProgramRun.expected(test, @runner.recordings) if test.read("expected")
          if mode == :verify
            return [:error, "no expected output beside it: record it with `bin/zr-dev test --record #{ProgramSelection.label(test)}`"]
          end

          live(test)
        end
      end

      # What the reference ruby answers now.
      def live(test)
        ProgramRun.ruby(test, ruby: [RbConfig.ruby], env: Harness::Reference.env) || [:error, "the reference ruby did not finish"]
      end

      # Writes `test`'s files from the reference ruby (zr-dev expect).
      # Returns nil when nothing changed, else what did.
      def record(test)
        require_relative "../../tool/expect"
        Dev::Commands::Expect.new("expect").expect(test)
      end

      # The baseline allows `test` to fail: a failure is a skip with the
      # reason, and a pass fails, so the baseline stays current.
      def baselined(test, kind, detail)
        triple = @host ? "host" : @runner.target.triple
        case kind
        when :pass then [:fail, "this now passes: take it off test/baselines/#{triple}.txt"]
        when :skip then [kind, detail]
        else [:skip, "the #{triple} baseline allows this: #{@allowed.fetch(test.rel)}"]
        end
      end
    end
  end
end
