# frozen_string_literal: true

require "etc"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Writes the expected output of program tests from ruby 4.0.7, the only
    # reference for correct output (test/support/program_case.rb).
    #
    #   zr-dev expect                               every test whose program is newer
    #   zr-dev expect test/programs/core/string     an area
    #   zr-dev expect --all test/programs/lang      write again, also if not newer
    #   zr-dev expect --check                       write nothing; list what differs
    #
    # A test gets `foo.rb.expected` (stdout), and `foo.rb.err.expected` and
    # `foo.rb.status` only when stderr is not empty or the status is not
    # `exit 0`. On linux the stdout goes to `foo.rb.linux.expected` when it
    # is not the same as `foo.rb.expected`. When ruby does not finish, the
    # old files stay.
    class Expect < Command
      summary "Write the expected output of program tests from ruby 4.0.7"
      usage "[--all] [--check] [path...]"
      host_ruby!

      def options(o)
        o.on("--all", "write every test, also one whose files are newer than its program") { @all = true }
        o.on("--check", "write nothing; list each test whose files differ from ruby") { @check = true }
      end

      def run(argv)
        Dev.pinned!(name)
        require_relative "../test/support/program_run"
        require_relative "../test/support/harness/reference"
        require_relative "../lib/zr/native/parallel"
        root = Dev.path("test/programs")
        argv = [root] if argv.empty?
        tests = argv.flat_map { |path| candidates(File.expand_path(path), root) }.uniq
        tests.select! { |test| stale?(test) } unless @all || @check
        results = Native::Parallel.map(tests, jobs: [Etc.nprocessors, 12].min, weight: ->(_) { 1 }) { |test| expect(test) }
        changed = tests.zip(results).filter_map { |test, result| "#{test.rel}: #{result}" if result }
        changed.each { |line| puts line }
        puts format("%d test(s) asked, %d %s", tests.size, changed.size, @check ? "differ from ruby" : "written")
        !@check || changed.empty?
      end

      # The programs below `path`, with or without expected output yet.
      def candidates(path, root)
        paths = File.file?(path) ? [path] : Dir[File.join(path, "**/*.rb")].sort
        paths.reject { |file| file.include?(".rb.files/") }.map { |file| Test::Case.new(root, file.delete_prefix(File.join(root, ""))) }
      end

      # A test whose expected output is missing or older than its program.
      def stale?(test)
        expected = test.beside("expected")
        !File.file?(expected) || File.mtime(expected) < File.mtime(test.path)
      end

      # Runs ruby on `test` and writes its files. Returns nil when nothing
      # changed, else what did.
      def expect(test)
        answer = Test::ProgramRun.ruby(test, ruby: [Dev.ruby], env: Harness::Reference.env)
        return "ruby did not finish; the old files stay" unless answer

        want = files_for(test, answer)
        changed = want.reject { |suffix, bytes| test.read(suffix) == bytes }
        return nil if changed.empty?
        return "differs: #{changed.keys.join(", ")}" if @check

        changed.each do |suffix, bytes|
          bytes ? File.binwrite(test.beside(suffix), bytes) : File.delete(test.beside(suffix))
        end
        "wrote #{changed.keys.join(", ")}"
      end

      # `{ suffix => bytes }` for each sidecar of `answer`; nil removes one.
      def files_for(test, answer)
        status = answer.signal ? "signal #{answer.signal}\n" : "exit #{answer.code}\n"
        out = { "err.expected" => (answer.stderr unless answer.stderr.empty?),
                "status" => (status unless status == "exit 0\n") }
        if RUBY_PLATFORM.include?("linux")
          out["linux.expected"] = (answer.stdout unless answer.stdout == test.read("expected"))
        else
          out["expected"] = answer.stdout
        end
        out
      end
    end
  end
end
