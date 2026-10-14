# frozen_string_literal: true

require "test_helper"

# The tests that test/baselines/upgrade.txt lists (test/support/pending.rb):
# a listed failure is a skip, a listed pass fails, and with no list the
# hook reads nothing about the test.
class PendingTest < Minitest::Test
  Pending = Zr::Test::Pending

  # A test that the cases below run by hand, one result at a time.
  class Probe < Minitest::Test
    def self.runnable_methods = []

    def test_probe = nil
  end

  def test_a_test_pays_nothing_without_an_upgrade_list
    probe = Probe.new(:test_probe)
    stub_method(Pending, :reasons, {}) do
      stub_method(Pending, :key, ->(_) { flunk "the hook read the key of a test with no list" }) do
        probe.after_teardown
      end
    end
    assert_empty probe.failures
  end

  def test_a_listed_failure_skips_with_its_reason
    probe = Probe.new(:test_probe)
    probe.failures << Minitest::Assertion.new("no")
    listed(probe) { probe.after_teardown }
    assert_equal ["pending in test/baselines/upgrade.txt: a new ruby"], probe.failures.map(&:message)
    assert_kind_of Minitest::Skip, probe.failures.first
  end

  def test_a_listed_pass_fails
    probe = Probe.new(:test_probe)
    listed(probe) { probe.after_teardown }
    assert_equal ["probe#test_probe passes now: remove its line from test/baselines/upgrade.txt"], probe.failures.map(&:message)
  end

  private

  def listed(probe, &)
    stub_method(Pending, :reasons, { "probe#test_probe" => "a new ruby" }) do
      stub_method(Pending, :key, ->(test) { test.equal?(probe) ? "probe#test_probe" : nil }, &)
    end
  end
end
