# frozen_string_literal: true

require_relative "flag"
require "fileutils"

module Zr
  module Test
    # Line and branch coverage of lib/, with `COVERAGE=1` (SimpleCov, in
    # the Gemfile). The report is tmp/coverage/index.html. A run without
    # `COVERAGE` does not load SimpleCov.
    #
    # test_helper.rb starts it before it loads zr: a file that loads
    # earlier has no coverage. lib/zr/runtime is not in the report. zr compiles that
    # code, and ruby does not run it.
    #
    # The tests run in forked workers (`ForkPool`). SimpleCov starts itself
    # again in each fork, and each fork stores its result with a name of
    # its own. The parent merges all results when it ends. A worker ends
    # with `exit!`, which skips SimpleCov's `at_exit`, and the parent stops
    # an idle worker at once. So `install` makes a worker store its result
    # before `exit!`, and makes the parent wait for that.
    #
    # It is not named `Coverage`: that would hide ruby's own `Coverage`
    # from the tests in this namespace.
    module CoverageRun
      DIRECTORY = "tmp/coverage"
      # Seconds that the parent waits for an idle worker to store its
      # result.
      PATIENCE = 30.0

      module_function

      # `COVERAGE=1`. It is asked before zr loads.
      def requested? = Zr::Test.flag?("COVERAGE")

      # Starts SimpleCov, unless it runs. Removes the results of an
      # earlier run first, so that the report is of this run only.
      def start(root:)
        require "simplecov"
        return if ::Coverage.running?

        FileUtils.rm_rf(File.join(root, DIRECTORY))
        SimpleCov.start do
          root(root)
          coverage_dir(DIRECTORY)
          enable_coverage(:branch)
          # Each forked worker stores its own result, and the parent
          # merges them.
          merge_subprocesses(true)
          # The files of lib/ that no test loads are in the report too.
          cover("lib/**/*.rb")
          skip("/lib/zr/runtime/")
        end
      end

      # Makes the workers of `worker` (`ForkPool::Worker`) store their
      # coverage before they end.
      def install(worker)
        worker.singleton_class.prepend(StoreBeforeExit)
        worker.prepend(WaitForExit)
      end

      # The worker ends with `exit!(0)`, which runs no `at_exit`. SimpleCov's
      # own exit step stores the result of this process.
      module StoreBeforeExit
        def exit!(status = 0)
          SimpleCov.at_exit_behavior
          super
        end
      end

      # `stop!` sends SIGTERM at once. A worker that has no more work
      # sees its pipe close and ends by itself, so wait for that first.
      module WaitForExit
        def stop!
          reap(PATIENCE) || super
        end
      end
    end
  end
end
