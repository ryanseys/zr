# frozen_string_literal: true

require "test_helper"

# Every test flag reads as Zr::Test.flag? does (test/support/flag.rb).
class FlagTest < Minitest::Test
  def test_a_flag_is_on_unless_it_is_unset_empty_or_zero
    { nil => false, "" => false, "0" => false, "1" => true, "yes" => true, "2" => true }.each do |value, on|
      with_env("ZR_FLAG_PROBE" => value) do
        assert_equal on, Zr::Test.flag?("ZR_FLAG_PROBE"), value.inspect
        assert_equal value.to_s.empty? || on, Zr::Test.flag?("ZR_FLAG_PROBE", default: true), value.inspect
      end
    end
  end

  def test_bless_zero_rewrites_nothing
    with_env("ZR_BLESS" => "0") { refute_predicate Checks, :bless? }
    with_env("ZR_BLESS" => "1") { assert_predicate Checks, :bless? }
  end
end
