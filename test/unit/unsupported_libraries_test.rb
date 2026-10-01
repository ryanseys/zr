# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"
require_relative "../../lib/zr/runtime"

# A library that ruby includes and zr has no file for stops with a
# message that gives its name. Most stop because the work is not done.
# A few stop because of a design decision, and their message gives the
# decision.
#
# The stop message reads "<what> is not implemented yet"
# (`zr_raise_stop`). Both paths to it must give the same text: a require
# that the compiler reads as a literal, and a require whose name the
# program computes, which reads the reason from the table in the program.
class UnsupportedLibrariesTest < Minitest::Test
  Build = Zr::Hir::Build

  def test_a_name_with_a_reason_stops_with_that_reason
    assert_equal "mkmf, which writes a C extension's Makefile: zr compiles no C, so an extension it configured",
                 stop(%(require "mkmf"\n))
  end

  def test_a_name_with_no_reason_stops_with_the_name
    assert_equal %(require of "ractor"), stop(%(require "ractor"\n))
  end

  def test_every_reason_is_for_a_library_with_no_file
    assert_equal Build::UNSUPPORTED_LIBRARIES.keys.sort, (Build::UNSUPPORTED_LIBRARIES.keys & Build.missing_features).sort
  end

  # The table in a program: the name, then a tab and the reason when
  # there is one. `Kernel.missing` reads the table.
  def test_load_names_table_has_the_reason_after_the_name
    rows = Zr::LoadTables.new(evals: true).data.find { |data| data.name == "zr_load_names_1" }.bytes.chomp("\0").split("\n")

    assert_includes rows, "mkmf\t#{Build::UNSUPPORTED_LIBRARIES.fetch("mkmf")}"
    assert_includes rows, "ractor"
  end

  private

  # The reason that the only statement of `source` stops for.
  def stop(source)
    node = Zr::Hir.build(source, "uncarried.rb").body.stmts.last

    assert_instance_of Zr::Hir::Stop, node
    node.what
  end
end
