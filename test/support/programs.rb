# frozen_string_literal: true

require_relative "baseline"
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
      ROOT = ProgramSelection::ROOT

      # Which tests a run has, and where their expected output comes from
      # (test/support/program_selection.rb).
      def self.mode = ProgramSelection.mode
      def self.cases(...) = ProgramSelection.cases(...)
      def self.label(...) = ProgramSelection.label(...)

      attr_reader :runner

      def initialize(target: Harness.selected_target, host: false, allowed: host ? Baseline.host : Baseline.for(target))
        @runner = Harness::Runner.new(ProgramBuild::ROOT, target)
        @allowed = allowed
        @host = host
      end

      def host? = @host

      # Why the baseline allows `test` to fail, or nil. A baseline names
      # only programs below test/programs.
      def baseline(test) = test.root == ROOT ? @allowed[test.rel] : nil

      # `[kind, detail]` for one test.
      def check(test)
        kind, detail = unmet(test) ? [:skip, unmet(test)] : outcome(test)
        baseline(test) ? baselined(test, kind, detail) : [kind, detail]
      end

      # Why this machine cannot run `test`, or nil.
      def unmet(test)
        return @runner.refusal if @runner.refusal

        platforms, needs = test.needs.partition { |name| Harness::Runner::PLATFORMS.value?(name) }
        return "runs only on #{platforms.join(", ")}" unless platforms.empty? || platforms.include?(@runner.platform)

        need = needs.find { |name| !Harness::Needs.met?(name, @runner.platform) }
        "needs #{need}" if need
      end

      def outcome(test, mode: ProgramSelection.mode)
        want = expected(test, mode)
        return want if want.is_a?(Array)

        got = @host ? HostProgram.answer(test, @runner) : ProgramBuild.answer(test, @runner)
        return [:error, got.join(": ")] if got.is_a?(Array)

        same = %i[stdout stderr code signal].all? { |part| want.public_send(part) == got.public_send(part) }
        same ? [:pass, nil] : [:fail, Diff.of(want, got)]
      end

      # The answer that `test` expects in `mode` (`MODES`), or `[:error,
      # why]` when it has none.
      def expected(test, mode)
        case mode
        when :live then live(test)
        when :record
          written = Expected.record(test)
          return [:error, "zr-dev expect: #{written}"] if written&.start_with?("ruby did not finish")

          ProgramRun.expected(test, @runner.platform)
        else
          return ProgramRun.expected(test, @runner.platform) if test.read("expected")
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

      # zr-dev expect, for `record`: it writes the files of one test.
      module Expected
        module_function

        # Writes `test`'s files from the reference ruby. Returns nil when
        # nothing changed, else what did.
        def record(test)
          require_relative "../../tool/expect"
          Dev::Commands::Expect.new("expect").expect(test)
        end
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

      # A diff of two answers, part by part: unified lines for stdout and
      # stderr, and the exit status when it differs.
      module Diff
        module_function

        def of(want, got)
          out = []
          %i[stderr stdout].each do |part|
            a = want.public_send(part).b
            b = got.public_send(part).b
            next if a == b

            out << "--- expected #{part}\n+++ actual #{part}\n#{lines(a.lines, b.lines).join}"
          end
          out << "status: expected #{want.status}, actual #{got.status}" if want.status != got.status
          out.join("\n")
        end

        # The lines of `a` and `b`, each marked ` `, `-` or `+`, from their
        # longest common subsequence. Outputs of more than 2,000 lines
        # compare only up to the first difference, with its context.
        def lines(a, b)
          return head(a, b) if a.size * b.size > 4_000_000

          lcs = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
          (a.size - 1).downto(0) do |i|
            (b.size - 1).downto(0) do |j|
              lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : [lcs[i + 1][j], lcs[i][j + 1]].max
            end
          end
          i = j = 0
          out = []
          while i < a.size || j < b.size
            if i < a.size && j < b.size && a[i] == b[j]
              out << " #{a[i]}"
              i += 1
              j += 1
            elsif i < a.size && (j == b.size || lcs[i + 1][j] >= lcs[i][j + 1])
              out << "-#{a[i]}"
              i += 1
            else
              out << "+#{b[j]}"
              j += 1
            end
          end
          out.map { |line| line.end_with?("\n") ? line : "#{line}\n\\ no newline at end\n" }
        end

        def head(a, b)
          n = a.zip(b).index { |x, y| x != y } || [a.size, b.size].min
          [*a[[n - 3, 0].max...n].map { |line| " #{line}" }, *(("-#{a[n]}") if a[n]), *(("+#{b[n]}") if b[n]),
           "... (#{a.size} expected lines, #{b.size} actual lines)\n"]
        end
      end
    end
  end
end
