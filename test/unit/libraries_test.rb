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

  # rubygems and bundler are ruby's own copies, so bundler's build
  # metadata is ruby 4.0.7's (no build date), not that of a
  # rubygems-update gem.
  def test_rubygems_and_bundler_come_from_rubys_library
    pure = Zr::Hir::Build.pure
    lib = RbConfig::CONFIG["rubylibdir"]

    sources = %w[rubygems.rb bundler.rb bundler/build_metadata.rb].map { |rel| File.readlink(File.join(pure, rel)) }

    assert_equal %w[rubygems.rb bundler.rb bundler/build_metadata.rb].map { |rel| File.join(lib, rel) }, sources
  end

  def test_the_gem_depends_on_no_rubygems_update
    spec = Gem::Specification.load(File.join(ROOT, "zr.gemspec"))

    names = spec.runtime_dependencies.map(&:name)

    refute_includes names, "rubygems-update"
    assert_equal Zr::Libraries::PINS.keys.sort, names.sort
  end
end
