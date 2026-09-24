# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rbconfig"

# Tests the time limit on one example. If a worker does not reply within
# `ZR_TEST_TIMEOUT`, the pool kills it and reports its example as a
# failure, with the example's name. Thus a compile that loops, or a
# machine that swaps, costs one example and not the whole tier.
#
# The test runs its own suite in a child process, because this process
# already runs in the pool under test.
class ForkPoolTest < Minitest::Test
  SUITE = <<~'RUBY'
    require "test_helper"

    class Bounded < Minitest::Test
      def test_a_quick_one = assert(true)
      def test_one_that_never_returns = sleep(300)
      def test_a_slow_one_that_fails
        sleep(1.5)
        flunk("on purpose")
      end
    end
  RUBY

  def test_an_example_past_the_deadline_fails_by_name
    out, status = suite("3")

    assert_includes out, "Bounded#test_one_that_never_returns"
    assert_includes out, "the worker ran past 3s on this example"
    assert_includes out, "ZR_TEST_TIMEOUT changes the bound"
    refute_predicate status, :success?
  end

  def test_other_examples_still_run
    out, = suite("3")

    assert_match(/3 runs, 2 assertions, 1 failures, 1 errors/, out)
  end

  def test_the_deadline_is_three_minutes_unless_it_is_asked_for
    assert_equal 180, Zr::Test::ForkPool::DEADLINE
  end

  # A suite that is slow, but not stuck, can set its own time limit.
  class Patient < Minitest::Test
    def self.deadline = 600
  end

  def test_a_suite_may_ask_for_a_bound_of_its_own
    assert_equal 600, Zr::Test::ForkPool.deadline_for(Patient)
    assert_equal Zr::Test::ForkPool::DEADLINE, Zr::Test::ForkPool.deadline_for(ForkPoolTest)
  end

  # When the pool kills a worker, it also kills the processes that the
  # worker started. A zr build forks six processes. An orphan of a killed
  # worker kept its pipe open, and 100 MB, for eight minutes after the
  # example failed.
  SPAWNER = <<~'RUBY'
    require "test_helper"

    class Spawner < Minitest::Test
      def test_one_that_leaves_a_child
        File.write(ENV.fetch("ZR_POOL_PID"), spawn("sleep 300").to_s)
        sleep(300)
      end
    end
  RUBY

  def test_a_worker_past_the_deadline_takes_its_children_with_it
    Dir.mktmpdir("zr-pool-") do |work|
      kept = File.join(work, "pid")
      child(SPAWNER, work, "ZR_TEST_TIMEOUT" => "3", "ZR_POOL_PID" => kept)
      pid = Integer(File.read(kept))

      assert_raises(Errno::ESRCH, "the worker's child outlived it") { Process.kill(0, pid) }
    end
  end

  # The pool replaces a worker because of the memory that the worker
  # allocates, not the memory that it inherits. The parent loads the
  # compiler before it forks, so each worker shares a few hundred MB with
  # the parent. If that memory counted, the pool would replace a worker
  # after each example, and a fork is expensive.
  #
  # Each example reads all of the inherited string. A page of the parent
  # is not resident for the worker until the worker reads it, so the
  # worker's resident size grows as it reads. A baseline taken at fork
  # time, or a fixed limit, counts that growth against the worker. Only a
  # baseline taken after the first example does not.
  SHARER = <<~'RUBY'
    require "test_helper"

    # The parent allocates this, so each worker starts with it shared.
    # This suite tests that case.
    BALLAST = "x" * (200 << 20)

    class Thrifty < Minitest::Test
      3.times do |n|
        define_method(:"test_a_cheap_one_#{n}") do
          File.write(ENV.fetch("ZR_POOL_PIDS"), "#{Process.pid}\n", mode: "a")
          assert_equal BALLAST.bytesize, BALLAST.count("x")
        end
      end
    end
  RUBY

  def test_worker_recycle_counts_only_memory_it_allocates
    Dir.mktmpdir("zr-pool-") do |work|
      kept = File.join(work, "pids")
      out, = child(SHARER, work, "ZR_TEST_RECYCLE_MB" => "150", "MT_CPU" => "1", "ZR_POOL_PIDS" => kept)

      assert_match(/3 runs, 3 assertions, 0 failures, 0 errors/, out)
      assert_equal 1, File.read(kept).lines.uniq.size,
                   "the worker was retired for memory it shares with the parent"
    end
  end

# Minitest does not catch `exit`, a signal or NoMemoryError, so these
# reach the worker loop. The worker reports the exception for the example
# that it ran, and does not exit silently ("exited 0 without answering").
# The examples after it run in a new worker.
LEAVER = <<~'RUBY'
  require "test_helper"

  class Leaver < Minitest::Test
    def test_a_one_that_exits = exit(0)
    def test_b_one_after_it = assert(true)
    def test_c_one_more = assert(true)
  end
RUBY

def test_exception_past_minitest_is_reported_for_its_example
  Dir.mktmpdir("zr-pool-") do |work|
    out, status = child(LEAVER, work, "MT_CPU" => "1")

    assert_includes out, "Leaver#test_a_one_that_exits"
    assert_includes out, "the example raised SystemExit past minitest: exit"
    refute_includes out, "without answering"
    assert_match(/3 runs, 2 assertions, 0 failures, 1 errors/, out)
    refute_predicate status, :success?
  end
end

  private

  # Runs SUITE in a child, with a limit of `timeout` seconds for each
  # example.
  def suite(timeout)
    Dir.mktmpdir("zr-pool-") { |work| child(SUITE, work, "ZR_TEST_TIMEOUT" => timeout) }
  end

  # Runs `source` as its own suite in `work`, and returns its output and
  # status. Do not name this `run`: `Minitest::Runnable` has a `run`, and
  # the pool would call this one in its place. The child gets a clean
  # bundler environment, because this process runs under bundler, and a
  # nested `bundle exec` refuses the load path that the test gives it.
  def child(source, work, env)
    file = File.join(work, "bounded_suite.rb")
    File.write(file, source)
    out = IO.popen(env, [RbConfig.ruby, "-I#{ROOT}/lib", "-I#{ROOT}/test", file], err: %i[child out], &:read)
    [out, $?]
  end
end
