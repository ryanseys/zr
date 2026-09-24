# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"
require_relative "../../lib/zr/runtime"

# A feature ruby carries that zr has no file for stops by name. Most of
# them stop because the work is not done; a few stop because the answer
# is a decision, and those say what the decision was.
#
# The stop reads "<what> is not implemented yet" (`zr_raise_stop`), and
# both roads to it must say the same thing: a require the compiler reads
# as a literal, and one whose name the program computes, which reads the
# reason off the table the program carries.
class UnsupportedLibrariesTest < Minitest::Test
  Build = Zr::Hir::Build

  def test_a_name_with_a_reason_stops_with_that_reason
    assert_equal "mkmf, which writes a C extension's Makefile: zr compiles no C, so an extension it configured",
                 stop(%(require "mkmf"\n))
  end

  def test_a_name_with_no_reason_stops_by_name
    assert_equal %(require of "ractor"), stop(%(require "ractor"\n))
  end

  def test_every_reason_is_for_a_name_no_root_holds
    assert_equal Build::UNSUPPORTED_LIBRARIES.keys.sort, (Build::UNSUPPORTED_LIBRARIES.keys & Build.missing_features).sort
  end

  # The table a program carries: the name, then the reason after a tab
  # where there is one, which `Kernel.missing` reads back.
  def test_the_table_a_program_carries_holds_the_reason_beside_the_name
    rows = Zr.load_tables([], evals: true).find { |data| data.name == "zr_load_names_1" }.bytes.split("\n")

    assert_includes rows, "mkmf\t#{Build::UNSUPPORTED_LIBRARIES.fetch("mkmf")}"
    assert_includes rows, "ractor"
  end

  private

  # What the only statement of `source` stops for.
  def stop(source)
    node = Zr::Hir.build(source, "uncarried.rb").body.stmts.last

    assert_instance_of Zr::Hir::Stop, node
    node.what
  end
end
