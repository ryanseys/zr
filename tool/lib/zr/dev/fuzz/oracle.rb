# frozen_string_literal: true

require "fileutils"

module Zr
  module Dev
    module Fuzz
      # Runs one program under ruby and as a zr binary, and gives the
      # verdict. Each program runs in a new directory of its own, as
      # `prog.rb`, so the two backtraces name the same file.
      #
      # A program that ruby cannot run within its limits, or that gives
      # ruby two answers, is no test of zr: its verdict is `invalid`. When
      # zr differs, the oracle runs both again: zr that gives two answers
      # is `flaky` (often a fault of the collector).
      class Oracle
        # The verdict, the answers (ruby's and zr's, Harness::Answer), the
        # build, and the seconds that the check took.
        Result = Struct.new(:verdict, :ruby, :zr, :build, :seconds, keyword_init: true) do
          def same? = verdict.same?
          def invalid? = verdict.kind == "invalid"
          def failure? = !same? && !invalid?
        end

        NAME = "prog.rb"

        # Seconds that ruby can take, and megabytes that a run can use.
        RUBY_SECONDS = 10
        MEGABYTES = 1024

        attr_reader :builder

        def initialize(builder:, work:, ruby_seconds: RUBY_SECONDS, keep: false)
          @builder = builder
          @work = work
          @ruby_seconds = ruby_seconds
          @keep = keep
          @count = 0
          @lock = Mutex.new
          FileUtils.mkdir_p(@work)
        end

        # The verdict of `source`. With `confirm`, a difference is checked
        # by a second run of each side.
        def check(source, confirm: true)
          (result, seconds) = Dev.timed { check_in(fresh_dir, source, confirm) }
          result.seconds = seconds
          result
        end

        # What ruby alone answers for `source` (the generator's own check).
        def ruby_only(source)
          dir = fresh_dir
          run = File.join(dir, "run")
          FileUtils.mkdir_p(run)
          File.binwrite(File.join(run, NAME), source)
          ruby(run)
        ensure
          FileUtils.rm_rf(dir) if dir && !@keep
        end

        private

        def check_in(dir, source, confirm)
          run = File.join(dir, "run")
          FileUtils.mkdir_p(run)
          File.binwrite(File.join(run, NAME), source)
          want, ruby_seconds = timed_ruby(run)
          return invalid("ruby #{want.code}", want) unless want.code.is_a?(Integer)

          bin = File.join(dir, "program")
          build = @builder.build(dir: run, file: NAME, out: bin)
          got = build.ok? ? binary(bin, run, ruby_seconds) : nil
          verdict = Classify.verdict(want, build, got)
          if confirm && !verdict.same? && build.ok?
            return invalid("ruby gives two answers", want) unless Classify.parts(ruby(run)) == Classify.parts(want)

            again = binary(bin, run, ruby_seconds)
            unless Classify.parts(again) == Classify.parts(got)
              verdict = Verdict.new(kind: "flaky", key: verdict.kind, detail: "zr gives two answers: #{verdict.detail}")
            end
          end
          Result.new(verdict: verdict, ruby: want, zr: got, build: build)
        ensure
          FileUtils.rm_rf(dir) unless @keep
        end

        def invalid(why, ruby) = Result.new(verdict: Verdict.new(kind: "invalid", key: why, detail: why), ruby: ruby)

        def fresh_dir
          n = @lock.synchronize { @count += 1 }
          dir = File.join(@work, n.to_s)
          FileUtils.mkdir_p(dir)
          File.realpath(dir)
        end

        def timed_ruby(run)
          Dev.timed { ruby(run) }
        end

        def ruby(run)
          answer, = Harness::Child.run([Dev.ruby, NAME], cwd: run, seconds: @ruby_seconds, megabytes: MEGABYTES,
                                                         env: Harness::Reference.env)
          normalize(answer, run)
        end

        # The binary gets twice ruby's time, and 5 seconds more for its
        # start.
        def binary(bin, run, ruby_seconds)
          answer, = Harness::Child.run([bin], cwd: run, seconds: [ruby_seconds * 2 + 5, 10].max, megabytes: MEGABYTES,
                                              env: @builder.env)
          normalize(answer, run)
        end

        def normalize(answer, run)
          return answer unless answer.code.is_a?(Integer) || answer.signal

          Harness::Normalize.answer(answer, File.join(run, NAME), run)
        end
      end
    end
  end
end
