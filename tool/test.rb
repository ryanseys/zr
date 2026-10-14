# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "lib/zr/dev/reach"
require_relative "../test/support/program_selection"

module Zr
  module Dev
    module Commands
      # `zr-dev test` runs zr's tests with bin/minitest. With no path it runs
      # every test. A path is a test file (with `:LINE` for the test on that
      # line, as minitest reads it), a directory of test files, or a Ruby
      # program or a directory of programs anywhere, which run as program
      # tests (test/programs_test.rb):
      #
      #   zr-dev test                                  every test
      #   zr-dev test test/unit/cli_test.rb:17         the test on line 17
      #   zr-dev test test/programs/core/gc            the programs below it
      #   zr-dev test scratch/try.rb                   a program of your own, against ruby now
      #   zr-dev test --suite unit,ext -n /help/       two suites, the tests whose name matches
      #   zr-dev test --changed                        the tests that the change reaches
      #   zr-dev test --failed                         the tests that failed last
      #   zr-dev test --slowest 30                     the 30 slowest tests that ran, and run nothing
      #
      # Each option sets what bin/minitest reads. The variable after an
      # option's text (`[MT_CPU]`) does the same without zr-dev; the option
      # wins.
      class Test < Command
        summary "Run zr's tests: all, or the test files, lines and programs given"
        usage "[options] [path[:line]...]"

        SUITES = { "unit" => "test/unit", "programs" => "test/programs", "ext" => "test/ext" }.freeze
        PROGRAMS_TEST = "test/programs_test.rb"
        PROGRAMS = Dev.path("test/programs")

        def defaults
          @env = {}
          @minitest = []
          @suites = []
          @changed = nil
          @failed = false
          @list = false
          @mode = nil
          @slowest = nil
        end

        def options(o)
          o.separator ""
          o.separator "Which tests:"
          o.on("-n", "--name PATTERN", "only the tests whose name matches (a /regexp/ or a string)") { |v| @minitest += ["--include", v] }
          o.on("-e", "--exclude PATTERN", "no test whose name matches") { |v| @minitest += ["--exclude", v] }
          o.on("--suite LIST", Array, "whole suites: #{SUITES.keys.join(", ")}") { |v| @suites |= v }
          o.on("--changed [BASE]", "the tests that the change against BASE (main) reaches") { |v| @changed = v || "main" }
          o.on("--failed", "the tests that failed and have not passed since") { @failed = true }
          o.separator ""
          o.separator "The expected output of a program test (with none, a program's files, else ruby now):"
          o.on("--record", "ask the reference ruby, and write the files beside each program first [ZR_EXPECTED=record]") { mode!("record") }
          o.on("--verify", "the files beside each program; a program with none fails [ZR_EXPECTED=verify]") { mode!("verify") }
          o.on("--live", "ask the reference ruby now; read and write no file [ZR_EXPECTED=live]") { mode!("live") }
          o.separator ""
          o.separator "How they run:"
          o.on("-s", "--seed N", Integer, "the order of the tests") { |v| @minitest += ["--seed", v.to_s] }
          o.on("-j", "--jobs N", Integer, "the worker processes [MT_CPU]") { |v| @env["MT_CPU"] = v.to_s }
          o.on("--target TRIPLE", "build and run the programs for that target [ZR_TARGET]") { |v| @env["ZR_TARGET"] = v }
          o.on("--gc-stress", "the programs collect at every allocation [ZR_GC_STRESS=1]") { @env["ZR_GC_STRESS"] = "1" }
          o.on("--no-build", "run the programs on CRuby over zr's kernel, with no build [ZR_TEST_HOST=1]") { @env["ZR_TEST_HOST"] = "1" }
          o.on("--no-cache", "run each test again, also one that passed with the same inputs [ZR_TEST_FRESH=1]") { @env["ZR_TEST_FRESH"] = "1" }
          o.on("--fail-fast", "run no more tests after one fails [ZR_TEST_FAIL_FAST=1]") { @env["ZR_TEST_FAIL_FAST"] = "1" }
          o.on("--timeout SECS", Integer, "the time limit of each test, and of each program's build and run",
               "[ZR_TEST_TIMEOUT, ZR_TEST_SECONDS]") do |v|
            @env["ZR_TEST_TIMEOUT"] = v.to_s
            @env["ZR_TEST_SECONDS"] = v.to_s
          end
          o.on("--list", "--dry-run", "print what would run, and run nothing") { @list = true }
          o.on("--slowest [N]", Integer, "print the N slowest tests and groups of the saved times (20), and run nothing") { |v| @slowest = v || 20 }
        end

        def run(argv)
          if @slowest
            print_slowest(@slowest)
            return true
          end

          paths = selected(argv)
          return true if paths.nil?

          files, programs = classify(paths)
          command = command(files, programs)
          return list(command) if @list

          Dev.pinned!(name) if needs_ruby?(programs)
          env, *argv = command
          exec(env, *argv, chdir: ROOT)
        end

        # The bin/minitest command: `[env, ruby, bin/minitest, *files,
        # *options]`.
        def command(files, programs)
          env = @env.dup
          env["ZR_EXPECTED"] = @mode if @mode
          # All of test/programs needs no list.
          env["ZR_PROGRAMS"] = programs.join(",") unless programs.empty? || programs == [PROGRAMS]
          files += [PROGRAMS_TEST] unless programs.empty? || files.include?(PROGRAMS_TEST)
          [env, Dev.ruby, Dev.path("bin/minitest"), *files, *@minitest]
        end

        # `[test files, programs]`: what bin/minitest gets, as paths below
        # the root, and what ZR_PROGRAMS gets, as full paths. Each path is
        # one of `paths`, below the current directory or absolute.
        def classify(paths)
          files = []
          programs = []
          paths.each do |arg|
            path, lines = arg.match(/\A(.*?)((?::\d+)+)?\z/).captures
            full = File.expand_path(path)
            fail!("no file or directory #{path}") unless File.exist?(full)

            if program?(full)
              fail!("#{arg}: a program is one test; give it with no line") if lines
              programs << full
            else
              files << "#{relative(full)}#{lines}"
            end
          end
          [files.uniq, programs.uniq]
        end

        private

        def mode!(mode)
          fail!("give one of --#{Zr::Test::ProgramSelection::MODES.join(", --")}") if @mode && @mode != mode
          @mode = mode
        end

        # The paths to run: the arguments, the suites, the changed tests and
        # the failed ones. Nil when a selection found nothing to run.
        def selected(argv)
          paths = argv.dup
          paths += @suites.map { |suite| Dev.path(SUITES.fetch(suite) { fail!("no suite #{suite}; the suites are #{SUITES.keys.join(", ")}") }) }
          if @changed
            changed = changed_paths(@changed)
            return nil if changed.nil?

            paths += changed
          end
          if @failed
            failed = failed_paths
            return nil if failed.nil?

            paths += failed
          end
          paths
        end

        # What the change against `base` reaches (`Dev::Reach`), or nil when
        # nothing.
        def changed_paths(base)
          files = Reach.files(base)
          tests = Reach.tests(files)
          # A full run is a decision for the user.
          if tests == :all
            puts "the change against #{base} reaches every test; `bin/zr-dev test` runs them all"
            return nil
          end
          return tests.map { |path| Dev.path(path) } unless tests.empty?

          puts "no test reaches the #{files.size} changed file(s) against #{base}"
          nil
        end

        # Prints the `count` slowest tests that the runs so far timed, with
        # the date of each time, and the groups that took the most time.
        def print_slowest(count)
          require_relative "../test/support/history"
          Zr::Test::History.merge
          rows = Zr::Test::History.current(Zr::Test::History.read.values)
          if rows.empty?
            puts "no test has a saved time yet (#{relative(Zr::Test::History::TABLE)}): run some tests first"
          else
            Zr::Test::History.report(rows, count, $stdout, dated: true)
          end
        end

        # The tests that failed and have not passed since, or nil when none.
        def failed_paths
          require_relative "../test/support/history"
          lines = Zr::Test::History.failed
          if lines.empty?
            puts "no test has failed since the last pass (#{relative(Zr::Test::History::FAILED)})"
            return nil
          end

          paths = lines.filter_map do |line|
            if line.start_with?("program ")
              label = line.delete_prefix("program ")
              [File.expand_path(label, PROGRAMS), File.expand_path(label, ROOT)].find { |path| File.exist?(path) }
            else
              path, number = line.split(":", 2)
              full = File.expand_path(path, ROOT)
              "#{full}:#{number}" if File.exist?(full)
            end
          end
          return paths unless paths.empty?

          # Never every test: the failures are gone, not the selection.
          puts "none of the #{lines.size} failed test(s) is there any more"
          nil
        end

        # Whether `full` is a program test or a directory of them, not a
        # minitest file or a directory of minitest files.
        def program?(full)
          return true if full == PROGRAMS || full.start_with?("#{PROGRAMS}/")
          return false if full.end_with?("_test.rb")

          !File.directory?(full) || Dir.glob("**/*_test.rb", base: full).empty?
        end

        def relative(full) = Pathname(full).relative_path_from(Pathname(ROOT)).to_s

        # Whether the run asks the reference ruby, which must be the pinned
        # one: to record or to answer live, or for a program that has no
        # expected output beside it.
        def needs_ruby?(programs)
          return true if %w[record live].include?(@mode)

          @mode.nil? && programs.any? { |path| File.file?(path) && !File.file?("#{path}.expected") }
        end

        # Prints the command and the tests that it runs.
        def list(command)
          env, *argv = command
          words = env.map { |name, value| "#{name}=#{value}" } + argv.map { |word| relative_word(word) }
          puts words.join(" ")
          files = argv.drop(2).reject { |word| word.start_with?("-") || @minitest.include?(word) }
          puts "  every test file: test/**/*_test.rb" if files.empty?
          files.each { |file| puts "  #{file}" unless file == PROGRAMS_TEST }
          list_programs(env) if files.include?(PROGRAMS_TEST) || files.empty?
          nil
        end

        def list_programs(env)
          selection = env.fetch("ZR_PROGRAMS") { ENV.fetch("ZR_PROGRAMS", "") }
          mode = env.fetch("ZR_EXPECTED") { ENV.fetch("ZR_EXPECTED", "") }
          # bin/minitest runs in the root, and names the tests from there.
          programs = Zr::Test::ProgramSelection.cases(selection, mode: mode.empty? ? nil : mode.to_sym, base: ROOT)
          cases = programs.map { |test| Zr::Test::ProgramSelection.label(test, base: ROOT) }
          puts "  #{PROGRAMS_TEST}: #{cases.size} program(s)"
          # All of test/programs is no list to read.
          cases.each { |label| puts "    #{label}" } if env.key?("ZR_PROGRAMS") || !ENV.fetch("ZR_PROGRAMS", "").empty?
        end

        def relative_word(word) = word.start_with?("#{ROOT}/") ? relative(word) : word
      end
    end
  end
end
