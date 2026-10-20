# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/programs"

# A program test times the parts of its build for `SLOW=1`
# (test/support/progress.rb): ProgramBuild adds the seconds of the lowering,
# the link and the run to the hash that it gets.
class ProgramBuildTest < Minitest::Test
  PROGRAM = "core/comparable/a_failed_comparison_names_its_reason.rb"

  def test_a_build_adds_the_time_of_each_part
    test = Zr::Test::ProgramSelection.cases(PROGRAM, base: Zr::Test::ProgramSelection::ROOT).fetch(0)
    parts = {}
    # A kept binary skips the lowering and the link.
    answer = with_env("ZR_TEST_BINARIES" => "0") { Zr::Test::ProgramBuild.answer(test, Zr::Test::Programs.new.runner, parts) }

    refute_kind_of Array, answer, "the program builds and runs"
    assert_equal %i[compile link lower run], parts.keys.sort
    assert(parts.except(:compile).values.all?(&:positive?), parts.inspect)
  end
end
