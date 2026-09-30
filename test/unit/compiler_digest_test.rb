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

  def test_the_digest_has_no_driver_file
    files = Zr::RuntimeSources.for(Zr::Target.default).compiler_files
    assert_empty files & Zr::RuntimeSources::DRIVER_ONLY
    assert_includes files, File.join(LIB, "zr/lower.rb")
  end
end
