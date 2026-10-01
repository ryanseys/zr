# frozen_string_literal: true

require "test_helper"

# THIRD_PARTY_NOTICES.md names each part of the gem that other people
# wrote. A runtime file whose header says that it follows other work
# (a copyright, a port, a C file it follows) must be in it, and every
# path in it must still name a file.
class NoticesTest < Minitest::Test
  NOTICES = File.read(File.join(ROOT, "THIRD_PARTY_NOTICES.md"))

  # The words in a header that name work from outside zr.
  SOURCE = /copyright|ported from|a port of|\bport under\b|libyaml|\bnkf\b|mt19937|onigmo|zlib 1\.|\bryu\b|fpconv|\b[a-z_0-9]+\.c\b/i

  def tracked(dir) = IO.popen(["git", "-C", ROOT, "ls-files", dir], &:read).split("\n")

  def paths = NOTICES.scan(/`([^`]+)`/).flatten.grep(%r{\A(lib/zr/runtime|vendor|licenses)/}).uniq

  def covered?(file)
    paths.any? { |path| File.fnmatch(path, file, File::FNM_PATHNAME) || file.start_with?("#{path.chomp("/")}/") }
  end

  def test_every_path_names_a_file
    files = tracked("lib/zr/runtime") + tracked("vendor") + tracked("licenses")

    stale = paths.reject { |path| files.any? { |file| File.fnmatch(path, file, File::FNM_PATHNAME) || file.start_with?("#{path.chomp("/")}/") } }

    assert_equal [], stale
  end

  def test_every_runtime_file_from_other_work_is_named
    derived = tracked("lib/zr/runtime").grep(/\.rb\z/).select { |file| File.foreach(File.join(ROOT, file)).first(20).join.match?(SOURCE) }

    missing = derived.reject { |file| covered?(file) }

    assert_equal [], missing
  end

  # A port's version changes in lib/zr/library/ports.rb and `zr-dev vendor`; its
  # row must change with it.
  def test_each_port_has_a_row_at_its_version
    missing = Zr::Library::Ports::ALL.filter_map do |name, port|
      "#{name} #{port.version}" if port.vendored && !NOTICES.include?("| #{name} | #{port.version} |")
    end

    assert_equal [], missing
  end

  def test_the_gem_ships_the_license_texts
    spec = Gem::Specification.load(File.join(ROOT, "zr.gemspec"))

    assert_equal tracked("licenses").sort, spec.files.grep(%r{\Alicenses/}).sort
    refute_empty tracked("licenses")
  end
end
