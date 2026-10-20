# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/ruby_version"

# THIRD_PARTY_NOTICES.md names each part of the gem that other people
# wrote. A runtime file whose header says that it follows other work
# (a copyright, a port, a C file it follows) must be in it, and every
# path in it must still name a file.
class NoticesTest < Minitest::Test
  NOTICES = File.read(File.join(ROOT, "THIRD_PARTY_NOTICES.md"))

  # The words in a header that name work from outside zr.
  SOURCE = /copyright|ported from|a port of|\bport under\b|libyaml|\bnkf\b|mt19937|onigmo|zlib 1\.|\bryu\b|fpconv|\b[a-z_0-9]+\.c\b/i

  def tracked(dir) = IO.popen(["git", "-C", ROOT, "ls-files", dir], &:read).split("\n")

  # The repository paths that the notices name. A heading names a whole
  # part (`lib/zr/runtime/`), not a file in it, so it covers nothing.
  # `<ruby_version>` in a path is the pinned ruby's library version.
  def paths
    NOTICES.lines.grep_v(/\A#/).join.scan(/`([^`]+)`/).flatten.grep(%r{\A(lib|vendor|licenses|benchmark)/}).uniq
           .map { |path| path.gsub("<ruby_version>", Zr::RUBY_LIB_VERSION) }
  end

  # Only a path below lib/zr/runtime/ covers a runtime file: a broad path
  # in the prose (`lib/`) covers nothing.
  def covered?(file)
    paths.grep(%r{\Alib/zr/runtime/.}).any? { |path| File.fnmatch(path, file, File::FNM_PATHNAME) || file.start_with?("#{path.chomp("/")}/") }
  end

  def test_every_path_names_a_file
    files = tracked("lib") + tracked("vendor") + tracked("licenses") + tracked("benchmark")

    stale = paths.reject { |path| files.any? { |file| File.fnmatch(path, file, File::FNM_PATHNAME) || file.start_with?("#{path.chomp("/")}/") } }

    assert_equal [], stale
  end

  def test_every_runtime_file_from_other_work_is_named
    derived = tracked("lib/zr/runtime").grep(/\.rb\z/).select do |file|
      File.foreach(File.join(ROOT, file)).first(20).grep(/\A\s*#/).join.match?(SOURCE)
    end

    missing = derived.reject { |file| covered?(file) }

    assert_equal [], missing
  end

  # Each runtime file that the notices name says so in its first lines,
  # so the notice stays with the file: a generated file through its
  # generator's header.
  def test_every_named_runtime_file_names_the_notices
    files = tracked("lib/zr/runtime").select do |file|
      paths.grep(%r{\Alib/zr/runtime/.+\.rb\z}).any? { |path| File.fnmatch(path, file, File::FNM_PATHNAME) }
    end
    bare = files.reject { |file| File.foreach(File.join(ROOT, file)).first(15).join.include?("THIRD_PARTY_NOTICES.md") }

    refute_empty files
    assert_equal [], bare, "add '# Derived from <part> (<license>); see THIRD_PARTY_NOTICES.md.' after the magic comments"
  end

  # A port's version changes in lib/zr/library/ports.rb and `zr-dev vendor`; its
  # row must change with it. Each vendored port has a row, and so has each
  # other port that the table names (psych, openssl, digest).
  def test_each_port_has_a_row_at_its_version
    missing = Zr::Library::Ports::ALL.filter_map do |name, port|
      named = port.vendored || NOTICES.include?("| #{name} | ")
      "#{name} #{port.version}" if named && !NOTICES.include?("| #{name} | #{port.version} |")
    end

    assert_equal [], missing
  end

  # A row that cites a section of ruby's LEGAL (`[missing/mt19937.c]`)
  # in place of a text in licenses/ must name a section that LEGAL has.
  def test_every_cited_legal_section_is_in_legal
    sections = File.foreach(File.join(ROOT, "vendor/LICENSES/ruby/LEGAL"), chomp: true).grep(/\A\[.+\]\z/)
    cited = NOTICES.scan(/`(\[[^`\]]+\])`/).flatten

    refute_empty cited
    assert_equal [], cited - sections
  end

  # Each text in licenses/ is there for a part that the notices name.
  def test_every_license_text_is_named
    unnamed = tracked("licenses").reject { |file| paths.include?(file) }

    assert_equal [], unnamed
  end

  # Each top-level entry of vendor/ (ruby, src, targets, LICENSES, the
  # lock) is a part with its own source and license.
  def test_every_part_of_vendor_is_named
    parts = tracked("vendor").map { |file| file.split("/").first(2).join("/") }.uniq

    unnamed = parts.reject { |part| paths.any? { |path| path == part || path.start_with?("#{part}/") } }

    assert_equal [], unnamed
  end

  def test_the_gem_ships_the_license_texts
    spec = Gem::Specification.load(File.join(ROOT, "zr.gemspec"))

    assert_equal tracked("licenses").sort, spec.files.grep(%r{\Alicenses/}).sort
    refute_empty tracked("licenses")
  end
end
