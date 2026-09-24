# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/cli"

# The command builds on the one ruby zr answers for, and no other: a
# build reads that ruby's standard library, and the tests hold zr to
# what that ruby said.
class CliTest < Minitest::Test
  def test_the_pinned_ruby_is_the_one_ruby_version_names
    assert_equal File.read(File.expand_path("../../.ruby-version", __dir__)).strip, Zr::RUBY
  end

  def test_the_pinned_ruby_builds
    assert_nil Zr::CLI.host_refusal(Zr::RUBY)
  end

  def test_another_ruby_is_refused_by_name
    assert_equal "zr #{Zr::VERSION} builds on ruby #{Zr::RUBY}, the ruby .ruby-version pins; this is ruby 4.0.7",
                 Zr::CLI.host_refusal("4.0.7")
  end

  def test_a_build_on_another_ruby_stops_with_the_refusal_status
    error = assert_raises(SystemExit) do
      assert_output(nil, "zr: #{Zr::CLI.host_refusal("4.0.7")}\n") { Zr::CLI.pinned!("4.0.7") }
    end
    assert_equal Zr::CLI::REFUSED, error.status
    assert_nil Zr::CLI.pinned!(Zr::RUBY)
  end
end
