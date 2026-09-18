# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rbconfig"

# The bound on one example. A worker that does not answer inside
# `ZE0_TEST_TIMEOUT` is killed and the example it was holding is reported
# as a failure by name, so a compile that loops -- or a machine that has
# begun to swap -- costs one example and not the whole tier.
#
# This runs a suite of its own in a child process, because the thing under
# test is the pool this process is already running in.
class ForkPoolTest < Minitest::Test
  SUITE = <<~'RUBY'
    require "test_helper"

    class Bounded < Minitest::Test
      def test_a_quick_one = assert(true)
      def test_one_that_never_answers = sleep(300)
      def test_a_slow_one_that_fails
        sleep(1.5)
        flunk("on purpose")
      end
    end
  RUBY

  def test_an_example_past_the_deadline_fails_by_name
    out, status = suite("3")

    assert_includes out, "Bounded#test_one_that_never_answers"
    assert_includes out, "the worker ran past 3s on this example"
    assert_includes out, "ZE0_TEST_TIMEOUT changes the bound"
    refute_predicate status, :success?
  end

  def test_the_examples_beside_it_still_answer
    out, = suite("3")

    assert_match(/3 runs, 2 assertions, 1 failures, 1 errors/, out)
  end

  def test_the_deadline_is_three_minutes_unless_it_is_asked_for
    assert_equal 180, Ze0::Test::ForkPool::DEADLINE
  end

  # A suite whose work is slow rather than stuck asks for its own bound.
  class Patient < Minitest::Test
    def self.deadline = 600
  end

  def test_a_suite_may_ask_for_a_bound_of_its_own
    assert_equal 600, Ze0::Test::ForkPool.deadline_for(Patient)
    assert_equal Ze0::Test::ForkPool::DEADLINE, Ze0::Test::ForkPool.deadline_for(ForkPoolTest)
  end

  # A worker that has to be killed takes with it whatever it started. A
  # ze0 build forks six more processes, and one orphaned by a killed
  # worker held its pipe open, and a hundred megabytes, for eight minutes
  # after the run had given up on the example.
  SPAWNER = <<~'RUBY'
    require "test_helper"

    class Spawner < Minitest::Test
      def test_one_that_leaves_a_child
        File.write(ENV.fetch("ZE0_POOL_PID"), spawn("sleep 300").to_s)
        sleep(300)
      end
    end
  RUBY

  def test_a_worker_past_the_deadline_takes_its_children_with_it
    Dir.mktmpdir("ze0-pool-") do |work|
      kept = File.join(work, "pid")
      child(SPAWNER, work, "ZE0_TEST_TIMEOUT" => "3", "ZE0_POOL_PID" => kept)
      pid = Integer(File.read(kept))

      assert_raises(Errno::ESRCH, "the worker's child outlived it") { Process.kill(0, pid) }
    end
  end

  # A worker is retired for what it has allocated, and not for what it
  # was born holding. The parent warms the compiler before it forks, so
  # every worker starts out resident in a few hundred megabytes that it
  # shares with the parent and never dirties. Counted against an
  # absolute bound, that head start would retire each worker after a
  # single example, and forking is the one thing here that is not free.
  #
  # Each example reads the whole of the inherited string, so the pages
  # really are the worker's resident set and not merely mapped.
  SHARER = <<~'RUBY'
    require "test_helper"

    # Held by the parent, so every worker is forked already resident in
    # it -- which is what this suite is about.
    BALLAST = "x" * (200 << 20)

    class Thrifty < Minitest::Test
      3.times do |n|
        define_method(:"test_a_cheap_one_#{n}") do
          File.write(ENV.fetch("ZE0_POOL_PIDS"), "#{Process.pid}\n", mode: "a")
          assert_equal BALLAST.bytesize, BALLAST.count("x")
        end
      end
    end
  RUBY

  def test_a_worker_is_retired_for_what_it_allocates_and_not_what_it_inherits
    Dir.mktmpdir("ze0-pool-") do |work|
      kept = File.join(work, "pids")
      out, = child(SHARER, work, "ZE0_RECYCLE_MB" => "150", "MT_CPU" => "1", "ZE0_POOL_PIDS" => kept)

      assert_match(/3 runs, 3 assertions, 0 failures, 0 errors/, out)
      assert_equal 1, File.read(kept).lines.uniq.size,
                   "the worker was retired for memory it shares with the parent"
    end
  end

  private

  # The suite run in a child, under `timeout` seconds an example.
  def suite(timeout)
    Dir.mktmpdir("ze0-pool-") { |work| child(SUITE, work, "ZE0_TEST_TIMEOUT" => timeout) }
  end

  # `source` run as a suite of its own in `work`, and what it said. Not
  # `run`: that is `Minitest::Runnable`'s own, and a private one here
  # would answer the pool in its place. The child gets a clean bundler
  # environment, since this process runs under one and a nested `bundle
  # exec` would refuse the load path we hand it.
  def child(source, work, env)
    file = File.join(work, "bounded_suite.rb")
    File.write(file, source)
    out = IO.popen(env, [RbConfig.ruby, "-I#{ROOT}/lib", "-I#{ROOT}/test", file], err: %i[child out], &:read)
    [out, $?]
  end
end
