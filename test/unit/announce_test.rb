# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# The first build of an installed zr fills the cache for minutes. It says
# so one time (`Zr::Runtime.announce`). A checkout says it only on a terminal, so
# a test that reads stderr gets nothing more.
class AnnounceTest < Minitest::Test
  def setup
    Zr::Runtime.instance_variable_set(:@announced, nil)
  end

  def teardown
    Zr::Runtime.instance_variable_set(:@announced, nil)
  end

  def test_an_installed_zr_says_one_time_that_it_builds_the_runtime
    target = Zr::Target::AARCH64_DARWIN
    installed do
      _, err = capture_io do
        Zr::Runtime.announce("the zr runtime", target)
        Zr::Runtime.announce("the zr runtime", target)
      end
      assert_equal "zr: building the zr runtime for aarch64-apple-darwin. This occurs one time and takes some minutes.\n", err
    end
  end

  def test_a_checkout_that_writes_to_a_pipe_says_nothing
    _, err = capture_io { Zr::Runtime.announce("the zr runtime", Zr::Target::AARCH64_DARWIN) }
    assert_empty err
  end

  private

  def installed
    stub_method(Zr::Paths, :checkout?, false) { yield }
  end
end
