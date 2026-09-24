# frozen_string_literal: true

require "test_helper"
require "ze0/hir/build"

# The library tree a build requires from (lib/ze0/libraries.rb): each
# root the loader searches is there, and holds what a require of it
# reads.
class LibrariesTest < Minitest::Test
  def test_every_library_root_is_a_directory
    roots = Ze0::Hir::Build.stdlib(Ze0::Target.default)

    missing = roots.reject { |root| File.directory?(root) }

    assert_equal [], missing
  end

  def test_the_tree_holds_a_default_gem_a_bundled_gem_and_the_residue
    pure = Ze0::Hir::Build.pure

    found = %w[net/http.rb csv.rb rubygems.rb bundler.rb pathname.rb].reject { |rel| File.file?(File.join(pure, rel)) }

    assert_equal [], found
  end

  def test_a_gem_kept_apart_has_its_own_lib
    apart = Ze0::Hir::Build.bundled

    held = apart.map { |dir| File.file?(File.join(dir, "#{File.basename(File.dirname(dir))}.rb")) }

    assert_equal [true] * Ze0::Libraries::APART.size, held
  end
end
