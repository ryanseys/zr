# frozen_string_literal: true

require "test_helper"
require "zr/hir/build"

# Tests the library tree that a build requires files from
# (lib/zr/libraries.rb). Each root that the loader searches must exist
# and contain the files that a require reads.
class LibrariesTest < Minitest::Test
  def test_every_library_root_is_a_directory
    roots = Zr::Hir::Build.stdlib(Zr::Target.default)

    missing = roots.reject { |root| File.directory?(root) }

    assert_equal [], missing
  end

  def test_pure_tree_contains_default_and_bundled_gems
    pure = Zr::Hir::Build.pure

    found = %w[net/http.rb csv.rb rubygems.rb bundler.rb pathname.rb].reject { |rel| File.file?(File.join(pure, rel)) }

    assert_equal [], found
  end

  def test_a_gem_kept_apart_has_its_own_lib
    apart = Zr::Hir::Build.bundled

    held = apart.map { |dir| File.file?(File.join(dir, "#{File.basename(File.dirname(dir))}.rb")) }

    assert_equal [true] * Zr::Libraries::APART.size, held
  end
end
