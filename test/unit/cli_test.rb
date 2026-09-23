# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/cli"

# The command builds on the one ruby ze0 answers for, and no other: a
# build reads that ruby's standard library, and the tests hold ze0 to
# what that ruby said.
class CliTest < Minitest::Test
  def test_the_pinned_ruby_is_the_one_ruby_version_names
    assert_equal File.read(File.expand_path("../../.ruby-version", __dir__)).strip, Ze0::RUBY
  end

  def test_the_pinned_ruby_builds
    assert_nil Ze0::CLI.host_refusal(Ze0::RUBY)
  end

  def test_another_ruby_is_refused_by_name
    assert_equal "ze0 #{Ze0::VERSION} builds on ruby #{Ze0::RUBY}, the ruby .ruby-version pins; this is ruby 4.0.7",
                 Ze0::CLI.host_refusal("4.0.7")
  end

  def test_a_build_on_another_ruby_stops_with_the_refusal_status
    error = assert_raises(SystemExit) do
      assert_output(nil, "ze0: #{Ze0::CLI.host_refusal("4.0.7")}\n") { Ze0::CLI.pinned!("4.0.7") }
    end
    assert_equal Ze0::CLI::REFUSED, error.status
    assert_nil Ze0::CLI.pinned!(Ze0::RUBY)
  end
end
