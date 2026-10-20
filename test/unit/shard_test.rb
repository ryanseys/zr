# frozen_string_literal: true

require "test_helper"

# `ZR_TEST_SHARD=I/N` (test/support/shard.rb) splits the examples into N
# parts that do not overlap and that hold every example together.
class ShardTest < Minitest::Test
  Shard = Zr::Test::Shard
  NAMES = Array.new(500) { |i| "test_#{i}" }

  def test_the_shards_hold_each_example_once
    parts = (1..4).map { |index| NAMES.select { |name| Shard.mine?("SomeTest", name, index, 4) } }

    assert_equal NAMES.sort, parts.flatten.sort
    parts.combination(2).each { |a, b| assert_empty a & b }
    parts.each { |part| assert_operator part.size, :>, 80, "a shard of 500 examples holds about 125" }
  end

  def test_a_bad_shard_is_refused
    assert_nil Shard.parse(nil)
    assert_nil Shard.parse("")
    assert_equal [2, 4], Shard.parse("2/4")
    %w[0/4 5/4 2 a/b 1/0].each do |spec|
      error = assert_raises(ArgumentError) { Shard.parse(spec) }
      assert_includes error.message, "ZR_TEST_SHARD is #{spec.inspect}"
    end
  end

  def test_the_filter_keeps_only_this_shard
    # Not a Minitest class, so that the run does not run its examples.
    klass = Class.new do
      def self.filter_runnable_methods(_options = {}) = NAMES
      def self.to_s = "ShardTest::Fake"
    end
    klass.singleton_class.prepend(Shard::Filter)
    with_env("ZR_TEST_SHARD" => "1/4") do
      kept = klass.filter_runnable_methods
      assert_equal NAMES.select { |name| Shard.mine?("ShardTest::Fake", name, 1, 4) }.sort, kept.sort
    end
    with_env("ZR_TEST_SHARD" => nil) { assert_equal NAMES.size, klass.filter_runnable_methods.size }
  end
end
