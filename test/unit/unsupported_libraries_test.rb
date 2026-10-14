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
    assert_equal "mkmf, which writes a C extension's Makefile: zr runs it in the host ruby when it builds a gem's extension, so mkmf in a program",
                 stop(%(require "mkmf"\n))
  end

  def test_a_name_with_no_reason_stops_with_the_name
    name = unreasoned or skip "every library of this ruby that zr has no file for has a reason"

    assert_equal %(require of "#{name}"), stop(%(require "#{name}"\n))
  end

  # The list follows the library roots, which the environment decides, so
  # a new session (a warm server's next build) reads it again.
  def test_missing_features_follow_the_roots_of_a_new_session
    target = Zr::Target.default
    name = Build.missing_features(target).first
    Dir.mktmpdir("zr-roots-") do |root|
      file = File.join(root, "#{name}.rb")
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, "")
      Zr::Session.current.reset!(keep_runtimes: true)
      Zr::Session.current.set([:stdlib, target.triple], [root])

      refute_includes Build.missing_features(target), name
    ensure
      Zr::Session.current.reset!(keep_runtimes: true)
    end
    assert_includes Build.missing_features(target), name
  end

  def test_every_reason_is_for_a_library_with_no_file
    assert_equal Build::UNSUPPORTED_LIBRARIES.keys.sort, (Build::UNSUPPORTED_LIBRARIES.keys & Build.missing_features).sort
  end

  # The table in a program: the name, then a tab and the reason when
  # there is one. `Kernel.missing` reads the table.
  def test_load_names_table_has_the_reason_after_the_name
    rows = Zr::LoadTables.new(computed: true).data.find { |data| data.name == "zr_load_names_1" }.bytes.chomp("\0").split("\n")

    assert_includes rows, "mkmf\t#{Build::UNSUPPORTED_LIBRARIES.fetch("mkmf")}"
    name = unreasoned
    assert_includes rows, name if name
  end

  private

  # A library that ruby includes, zr has no file for and no reason,
  # and that is not an encoding (which a require loads at run time).
  def unreasoned
    (Build.missing_features - Build::UNSUPPORTED_LIBRARIES.keys).find { |name| !name.match?(Build::ENCODINGS) }
  end

  # The reason that the only statement of `source` stops for.
  def stop(source)
    node = Zr::Hir.build(source, "uncarried.rb").body.stmts.last

    assert_instance_of Zr::Hir::Stop, node
    node.what
  end
end
