# frozen_string_literal: true

require "test_helper"
require "zr/library/roots"

# Tests zr's standard library (vendor/ruby, lib/zr/library/roots.rb) and the
# gems whose C part zr ports (lib/zr/library/ports.rb). A build reads a
# program's library from these, and never from the host's gems.
class LibraryRootsTest < Minitest::Test
  Library = Zr::Library

  def test_every_library_root_is_a_directory
    roots = Library::Roots.stdlib(Zr::Target.default)

    missing = roots.reject { |root| File.directory?(root) }

    assert_equal [], missing
  end

  def test_ruby_lib_holds_the_default_gems_and_rubygems
    pure = Library::Roots.pure

    found = %w[net/http.rb rubygems.rb bundler.rb pathname.rb syntax_suggest/api.rb].reject { |rel| File.file?(File.join(pure, rel)) }

    assert_equal [], found
  end

  # A compiled compiler with eval support reads its library roots from
  # its load tables (`LoadTables#texts`, the first text), also when the
  # build had a GemSet: ruby's library, then the bundled gems.
  def test_the_load_tables_carry_ruby_lib_and_the_bundled_gems
    require "zr/load_tables"
    shown = Library::Roots.bundled_roots.map { |root| Zr::Paths.shown(root) }

    found = [[], ["/gems/a/lib"]].map do |gem_roots|
      Library::Roots.from_load_names(Zr::LoadTables.new(computed: true, gem_roots: gem_roots).texts.first)
    end

    assert_equal [[Zr::Paths.shown(Library::Roots.pure), shown]] * 2, found
  end

  def test_each_bundled_gem_is_installed_in_its_own_directory
    held = Library::Stdlib::BUNDLED.zip(Library::Roots.bundled_roots).reject do |(name, version), dir|
      dir.end_with?("/gems/#{name}-#{version}/lib") && File.file?(File.join(dir, "..", "..", "..", "specifications", "#{name}-#{version}.gemspec"))
    end

    assert_equal [], held
  end

  # The versions are stock ruby 4.0.7's (`zr-dev vendor` reads them
  # from ruby itself), so each default gem's specification is this ruby's.
  def test_default_gems_are_this_rubys_versions
    stale = Library::Stdlib::DEFAULT.reject do |name, version|
      File.file?(File.join(Gem.default_specifications_dir, "#{name}-#{version}.gemspec"))
    end

    assert_equal({}, stale)
  end

  # A port gem is vendored at zr's version, and no bundled gem of that
  # name is. A port with no gem here has its Ruby half in ruby's own
  # library, so that copy must be the port's version.
  def test_each_port_is_one_version
    bundled = Library::Ports::ALL.select { |_, port| port.vendored }.keys & Library::Stdlib::BUNDLED.keys
    stock = Library::Ports::ALL.reject { |name, port| port.vendored || [nil, port.version].include?(Library::Stdlib::DEFAULT[name]) }

    assert_equal [], bundled
    assert_equal({}, stock)
  end

  # zr's own code comes first, then the port gems, then ruby's own
  # library: `require "json"` finds json 3.0.2, not ruby's 2.18.0.
  def test_ports_come_before_rubys_own_library
    roots = Library::Roots.stdlib(Zr::Target.default)

    json = roots.find { |root| File.file?(File.join(root, "json.rb")) }

    assert_equal 1, roots.index(Library::Layout::EXT)
    assert_equal Library::Ports.lib("json"), json
    assert_operator roots.index(json), :<, roots.index(Library::Roots.pure)
  end

  def test_each_ported_ruby_half_is_vendored
    missing = Library::Ports.roots.reject { |dir| File.directory?(dir) }

    assert_equal [], missing
  end

  def test_the_gem_depends_on_nothing
    spec = Gem::Specification.load(File.join(ROOT, "zr.gemspec"))

    assert_equal [], spec.runtime_dependencies.map(&:name)
    assert(spec.files.any? { |file| file.start_with?("vendor/ruby/lib/ruby/#{Zr::Library::Layout::API}/") })
  end
end
