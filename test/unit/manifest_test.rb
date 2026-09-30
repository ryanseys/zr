# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/manifest"
require_relative "../../lib/zr/gem_set"
require_relative "../../lib/zr/libraries"

# Which gem each file of a build comes from (lib/zr/manifest.rb): `zr
# gems` prints it, and each binary carries it for `zr inspect`.
class ManifestTest < Minitest::Test
  Manifest = Zr::Manifest

  def rows(*files, gem_set: nil) = Manifest.of(files, gem_set).map(&:to_a)

  def test_a_default_gems_file_is_that_gem
    assert_equal [["net-http", Zr::Stdlib::DEFAULT.fetch("net-http"), "stdlib"]], rows(File.join(Zr::Libraries::LIB, "net/http.rb"))
  end

  def test_a_bundled_gems_file_is_that_gem
    csv = File.join(Zr::Libraries.lib_of("csv"), "csv.rb")

    assert_equal [["csv", Zr::Stdlib::BUNDLED.fetch("csv"), "stdlib"]], rows(csv)
  end

  def test_a_ports_ruby_half_is_the_port
    json = File.join(Zr::Ports.lib("json"), "json.rb")

    assert_equal [["json", Zr::Ports::ALL.fetch("json").version, "port"]], rows(json)
  end

  def test_rubys_own_files_and_rubygems
    assert_equal [["ruby", Zr::RUBY, "stdlib"]], rows(File.join(Zr::Libraries::LIB, "pathname.rb"))
    assert_equal [["rubygems", Zr::Stdlib::RUBYGEMS, "stdlib"]], rows(File.join(Zr::Libraries::LIB, "rubygems/version.rb"))
  end

  def test_the_programs_own_files_have_no_row
    assert_equal [], rows("/app/main.rb", "/app/lib/greeter.rb")
  end

  # A `--gem` directory's path stays out of the manifest, so two machines
  # build the same bytes.
  def test_a_gem_of_the_gem_set_takes_its_files_without_its_path
    set = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "csv", version: "3.3.6", source: "--gem csv=/src/csv", roots: ["/src/csv/lib"], refusal: nil)])

    assert_equal [["csv", "3.3.6", "--gem"]], rows("/src/csv/lib/csv.rb", gem_set: set)
    assert_equal ["csv", "3.3.6", "--gem"], Manifest.all(set).find { |row| row.name == "csv" }.to_a
  end

  def test_all_lists_each_stdlib_gem_and_port_once
    names = Manifest.all.map(&:name)

    assert_equal names.uniq.sort, names
    assert_includes names, "csv"
    assert_includes names, "json"
  end

  def test_the_manifest_is_found_in_the_bytes_of_a_binary
    bytes = Manifest.bytes(rows(File.join(Zr::Libraries::LIB, "net/http.rb")).map { |r| Manifest::Row.new(*r) }, Zr::Target.default)
    # zr's own binary also has MAGIC as a string of lib/zr/manifest.rb.
    binary = "\x7fELF#{Manifest::MAGIC}not json\0junk#{bytes.chomp}\0more"

    found = Manifest.find(binary)

    assert_equal [Zr::VERSION, Zr::Target.default.triple, "net-http"], [found["zr"], found["target"], found["gems"].first["name"]]
    assert_nil Manifest.find("no manifest here")
  end
end
