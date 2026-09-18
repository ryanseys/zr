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

  private

  # The suite run in a child, under `timeout` seconds an example. The
  # child gets a clean bundler environment: this process runs under one,
  # and a nested `bundle exec` would refuse the load path we hand it.
  def suite(timeout)
    Dir.mktmpdir("ze0-pool-") do |work|
      file = File.join(work, "bounded_suite.rb")
      File.write(file, SUITE)
      out = IO.popen({ "ZE0_TEST_TIMEOUT" => timeout }, [RbConfig.ruby, "-I#{ROOT}/lib", "-I#{ROOT}/test", file],
                     err: %i[child out], &:read)
      [out, $?]
    end
  end
end
