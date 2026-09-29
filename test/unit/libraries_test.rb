# frozen_string_literal: true

require "test_helper"
require "zr/hir/build"

# Tests zr's standard library (stdlib/, lib/zr/libraries.rb) and the gems
# whose C part zr ports (lib/zr/ports.rb). A build reads a program's
# library from these, and never from the host's gems.
class LibrariesTest < Minitest::Test
  def test_every_library_root_is_a_directory
    roots = Zr::Hir::Build.stdlib(Zr::Target.default)

    missing = roots.reject { |root| File.directory?(root) }

    assert_equal [], missing
  end

  def test_ruby_lib_holds_the_default_gems_and_rubygems
    pure = Zr::Hir::Build.pure

    found = %w[net/http.rb rubygems.rb bundler.rb pathname.rb syntax_suggest/api.rb].reject { |rel| File.file?(File.join(pure, rel)) }

    assert_equal [], found
  end

  def test_each_bundled_gem_is_installed_in_its_own_directory
    held = Zr::Stdlib::BUNDLED.zip(Zr::Hir::Build.bundled).reject do |(name, version), dir|
      dir.end_with?("/gems/#{name}-#{version}/lib") && File.file?(File.join(dir, "..", "..", "..", "specifications", "#{name}-#{version}.gemspec"))
    end

    assert_equal [], held
  end

  # The versions are stock ruby 4.0.7's (`zr-dev gen stdlib` reads them
  # from ruby itself), so each default gem's specification is this ruby's.
  def test_default_gems_are_this_rubys_versions
    stale = Zr::Stdlib::DEFAULT.reject do |name, version|
      File.file?(File.join(Gem.default_specifications_dir, "#{name}-#{version}.gemspec"))
    end

    assert_equal({}, stale)
  end

  def test_no_ported_gem_is_in_the_stdlib
    both = Zr::Ports::ALL.keys & (Zr::Stdlib::DEFAULT.keys + Zr::Stdlib::BUNDLED.keys)

    assert_equal [], both
  end

  def test_each_ported_ruby_half_is_vendored
    missing = Zr::Ports.roots.reject { |dir| File.directory?(dir) }

    assert_equal [], missing
  end

  def test_the_gem_depends_on_nothing
    spec = Gem::Specification.load(File.join(ROOT, "zr.gemspec"))

    assert_equal [], spec.runtime_dependencies.map(&:name)
    assert(spec.files.any? { |file| file.start_with?("stdlib/lib/ruby/4.0.0/") })
  end
end
