# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# The compiler digest leaves out the files that only drive zr
# (`Zr::RuntimeSources::DRIVER_ONLY`), so an edit to them rebuilds nothing. That holds only
# while no build or link loads them: a file that a build loads can change
# its output.
class CompilerDigestTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  def test_a_build_and_a_link_load_no_driver_file
    code = <<~RUBY
      require "zr/runtime"
      require "zr/native/build"
      Zr::Native::Build.linker(Zr::Target.default)
      puts $LOADED_FEATURES.select { |f| Zr::RuntimeSources::DRIVER_ONLY.include?(f) }
    RUBY
    out, status = Open3.capture2(RbConfig.ruby, "-I#{LIB}", "-e", code)
    assert_predicate status, :success?
    assert_empty out.split("\n"), "a build loads a file of Zr::RuntimeSources::DRIVER_ONLY; take it out of the list"
  end

  # The compiler files that a plain build and link do not load, but that
  # other builds do, so they stay in the digest: eval support compiles the
  # eval compiler and its walker, a build with --gem loads the gem set, and
  # a listing, a diff, `zr-dev vendor` and the IR interpreter load the rest
  # on demand.
  LOADED_BY_SOME_BUILDS = %w[
    backend/aarch64/listing.rb diff.rb eval.rb eval/walk.rb eval/walk/tree.rb gem_set.rb gem_set/resolve.rb
    ir/interp.rb library.rb library/vendor.rb
  ].map { |name| File.join(LIB, "zr", name) }.freeze

  # The other side of the first test: a new file that only drives zr must
  # go in DRIVER_ONLY (or the list above), so that an edit to it does not
  # rebuild the runtime.
  def test_each_compiler_file_that_a_build_does_not_load_is_listed
    code = <<~RUBY
      require "zr/runtime"
      require "zr/native/build"
      Zr::Native::Build.linker(Zr::Target.default)
      loaded = $LOADED_FEATURES.to_h { |f| [f, true] }
      puts Zr::RuntimeSources.for(Zr::Target.default).compiler_files.reject { |f| loaded[f] }
    RUBY
    out, status = Open3.capture2(RbConfig.ruby, "-I#{LIB}", "-e", code)
    assert_predicate status, :success?
    unlisted = out.split("\n") - LOADED_BY_SOME_BUILDS
    assert_empty unlisted, "a build does not load these compiler files: add them to Zr::RuntimeSources::DRIVER_ONLY " \
                           "if no output depends on them, else to LOADED_BY_SOME_BUILDS"
  end

  # A compiler file counts by its code: an edit of a comment, a comment
  # line or a comment after code keeps the runtime's digest.
  def test_a_comment_edit_keeps_the_code_of_a_compiler_file
    plain = "# frozen_string_literal: true\n\ndef f\n  x = \"#not a comment\"\n  x\nend\n"
    commented = "# frozen_string_literal: true\n\n# Says what f does.\ndef f # f\n  # x is one\n  x = \"#not a comment\" # see\n  x\nend\n"

    assert_equal Zr::Digests.code(plain), Zr::Digests.code(commented)
    assert_includes Zr::Digests.code(commented), "# frozen_string_literal: true", "a magic comment changes what the code does"
    assert_includes Zr::Digests.code(commented), "\"#not a comment\""
    refute_equal Zr::Digests.code(plain), Zr::Digests.code(plain.sub("x\nend", "x + 1\nend"))
  end

  # A comment edit moves the lines of the code after it, and the code
  # digest does not see that. So no compiler file may read its own line.
  def test_no_compiler_file_reads_its_line
    files = Zr::RuntimeSources.for(Zr::Target.default).compiler_files.select { |path| Zr::Digests.compiler_file?(path) }
    readers = files.select { |path| Zr::Digests.code(File.binread(path)).include?("__LINE__") }
    assert_empty readers, "a compiler file reads __LINE__; its line can change with a comment edit"
  end

  def test_only_a_compiler_file_counts_by_its_code
    assert Zr::Digests.compiler_file?(File.join(LIB, "zr/lower.rb"))
    refute Zr::Digests.compiler_file?(File.join(Zr::Paths::RUNTIME, "core/array.rb")), "a binary holds the core's lines"
  end

  def test_the_digest_has_no_driver_file
    files = Zr::RuntimeSources.for(Zr::Target.default).compiler_files
    assert_empty files & Zr::RuntimeSources::DRIVER_ONLY
    assert_includes files, File.join(LIB, "zr/lower.rb")
  end
end
