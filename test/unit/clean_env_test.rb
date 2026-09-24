# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# A child process of the tests runs outside this bundle.
#
# `bundle exec` puts `bundler/setup` in `RUBYOPT` and in `BUNDLER_SETUP`.
# Thus a child ruby loads bundler before it reads its program. That ruby
# is different from a plain ruby: it gives out 56 object ids before the
# first line runs. It also refuses a gem that ruby bundles but that this
# Gemfile does not list.
class CleanEnvTest < Minitest::Test
  CleanEnv = Zr::Harness::CleanEnv

  def test_env_does_not_include_bundler
    refute_includes CleanEnv.env.fetch("RUBYOPT", ""), "bundler"
    refute_operator CleanEnv.env, :key?, "BUNDLER_SETUP"
  end

  def test_an_overlay_goes_over_it_and_a_nil_takes_a_variable_out
    assert_equal "1", CleanEnv.env("ZR_GC_STRESS" => "1").fetch("ZR_GC_STRESS")
    refute_operator CleanEnv.env("PATH" => nil), :key?, "PATH"
  end

  def test_a_child_of_a_check_has_not_loaded_bundler
    assert_equal "nil\n", ruby("p defined?(Bundler)")
  end

  # A plain ruby returns 16 for the first object id. After bundler runs,
  # it returns 464. Thus ruby and the binary under test gave different
  # output.
  def test_child_object_ids_start_where_plain_ruby_starts
    assert_equal "16\n", ruby(%(p "x".object_id))
  end

  private

  def ruby(source)
    Dir.mktmpdir("zr-unbundled-") do |work|
      rb = File.join(work, "child.rb")
      File.write(rb, source)
      answer = Checks.run([RbConfig.ruby, rb])
      assert_nil Checks.killed(answer)
      answer.stdout
    end
  end
end
