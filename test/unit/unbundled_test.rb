# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# A child of the checks runs outside this bundle.
#
# `bundle exec` names `bundler/setup` in `RUBYOPT` and again in
# `BUNDLER_SETUP`, so a ruby started from here loads bundler before it
# reads the program it was given. That ruby is not the ruby the contract
# names: it has handed out fifty-six object ids before the first line
# runs, and it refuses a gem ruby bundles but this Gemfile does not.
class UnbundledTest < Minitest::Test
  Unbundled = Ze0::Harness::Unbundled

  def test_the_environment_it_hands_out_does_not_carry_bundler
    refute_includes Unbundled.env.fetch("RUBYOPT", ""), "bundler"
    refute_operator Unbundled.env, :key?, "BUNDLER_SETUP"
  end

  def test_an_overlay_goes_over_it_and_a_nil_takes_a_variable_out
    assert_equal "1", Unbundled.env("ZR_GC_STRESS" => "1").fetch("ZR_GC_STRESS")
    refute_operator Unbundled.env("PATH" => nil), :key?, "PATH"
  end

  def test_a_child_of_a_check_has_not_loaded_bundler
    assert_equal "nil\n", ruby("p defined?(Bundler)")
  end

  # What the divergence was. ruby answers 16 for the first object id it
  # is asked for, and 464 once bundler has run first, so the oracle and
  # the binary it is compared with answered differently.
  def test_a_child_of_a_check_counts_object_ids_from_where_ruby_does
    assert_equal "16\n", ruby(%(p "x".object_id))
  end

  private

  def ruby(source)
    Dir.mktmpdir("ze0-unbundled-") do |work|
      rb = File.join(work, "child.rb")
      File.write(rb, source)
      out, why = Checks.bounded({}, [RbConfig.ruby, rb], err: File.join(work, "err"))
      assert_nil why
      out
    end
  end
end
