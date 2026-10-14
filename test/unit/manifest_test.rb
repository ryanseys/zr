# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/manifest"
require_relative "../../lib/zr/gem_set"
require_relative "../../lib/zr/library/roots"

# Which gem each file of a build comes from (lib/zr/manifest.rb): `zr
# gems` prints it, and each binary carries it for `zr inspect`.
class ManifestTest < Minitest::Test
  Manifest = Zr::Manifest

  def rows(*files, gem_set: nil) = Manifest.of(files, gem_set).map { |row| row.deconstruct.compact }

  def test_a_default_gems_file_is_that_gem
    http = File.join(Zr::Library::Layout::RUBYLIBDIR, "net/http.rb")

    assert_equal [["net-http", Zr::Library::Stdlib::DEFAULT.fetch("net-http"), "stdlib"]], rows(http)
  end

  def test_a_bundled_gems_file_is_that_gem
    csv = File.join(Zr::Library::Roots.lib_of("csv"), "csv.rb")

    assert_equal [["csv", Zr::Library::Stdlib::BUNDLED.fetch("csv"), "stdlib"]], rows(csv)
  end

  def test_a_ports_ruby_half_is_the_port
    json = File.join(Zr::Library::Ports.lib("json"), "json.rb")

    assert_equal [["json", Zr::Library::Ports::ALL.fetch("json").version, "port"]], rows(json)
  end

  def test_rubys_own_files_and_rubygems
    assert_equal [["ruby", Zr::RUBY, "stdlib"]], rows(File.join(Zr::Library::Layout::RUBYLIBDIR, "pathname.rb"))
    assert_equal [["rubygems", Zr::Library::Stdlib::RUBYGEMS, "stdlib"]], rows(File.join(Zr::Library::Layout::RUBYLIBDIR, "rubygems/version.rb"))
  end

  def test_the_programs_own_files_have_no_row
    assert_equal [], rows("/app/main.rb", "/app/lib/greeter.rb")
  end

  # The source of a `--gem` gem is only `--gem`, without the words of the
  # flag. Its row names the gem's directory, which the program gives as
  # the spec's full_gem_path: the directory where the build found it, as
  # the paths of its files are. So two machines that have the gem at one
  # path build the same bytes.
  def test_a_gem_of_the_gem_set_names_its_directory_and_not_its_flag
    set = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "csv", version: "3.3.6", source: "--gem csv=/src/csv", roots: ["/src/csv/lib"], refusal: nil)])

    assert_equal [["csv", "3.3.6", "--gem", "/src/csv"]], rows("/src/csv/lib/csv.rb", gem_set: set)
    assert_equal ["csv", "3.3.6", "--gem", nil], Manifest.all(set).find { |row| row.name == "csv" }.deconstruct
    assert_equal({ "name" => "csv", "version" => "3.3.6", "source" => "--gem", "dir" => "/src/csv" },
Manifest.of(["/src/csv/lib/csv.rb"], set).first.to_h)
  end

  def test_a_gem_whose_root_is_not_lib_names_its_root
    set = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "flat", version: "1.0", source: "--gem", roots: ["/src/flat"], refusal: nil)])

    assert_equal [["flat", "1.0", "--gem", "/src/flat"]], rows("/src/flat/flat.rb", gem_set: set)
  end

  # A program with eval can require any gem of its set at run time, so
  # each has a row, and one that the build refused has none.
  def test_a_program_with_eval_has_a_row_for_each_gem_of_its_set
    set = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "parser", version: "3.3.12.0", source: "--gem", roots: ["/src/parser/lib"], refusal: nil),
                          Zr::GemSet::Entry.new(name: "native", version: "1.0.0", source: "--gem", roots: ["/src/native/lib"],
                                                refusal: "native has a C extension")])

    assert_equal [], Manifest.of([], set).map(&:deconstruct)
    assert_equal [["parser", "3.3.12.0", "--gem", "/src/parser"]], Manifest.of([], set, evals: true).map(&:deconstruct)
  end

  # A program with eval carries its libraries in eval support, not in its
  # own units: `require "json"` there compiles no unit of json.
  def test_a_program_with_eval_has_the_rows_of_eval_supports_files
    hir = Struct.new(:units, :evals)
    support = Struct.new(:units).new({ File.join(Zr::Library::Ports.lib("json"), "json.rb") => "zr_eval_unit_1" })
    json = [["json", Zr::Library::Ports::ALL.fetch("json").version, "port"]]

    assert_equal json, Manifest.of_program(hir.new([], true), support).map { |row| row.deconstruct.compact }
    assert_equal [], Manifest.of_program(hir.new([], false), support).map(&:deconstruct)
  end

  def test_all_lists_each_stdlib_gem_and_port_once
    names = Manifest.all.map(&:name)

    assert_equal names.uniq.sort, names
    assert_includes names, "csv"
    assert_includes names, "json"
  end

  def test_the_manifest_is_found_in_the_bytes_of_a_binary
    bytes = Manifest.bytes(rows(File.join(Zr::Library::Layout::RUBYLIBDIR, "net/http.rb")).map { |r| Manifest::Row.new(*r) }, Zr::Target.default)
    # zr's own binary also has MAGIC as a string of lib/zr/manifest.rb.
    binary = "\x7fELF#{Manifest::MAGIC}not json\0junk#{bytes.chomp}\0more"

    found = Manifest.find(binary)

    assert_equal [Zr::VERSION, Zr::Target.default.triple, "net-http"], [found["zr"], found["target"], found["gems"].first["name"]]
    assert_nil Manifest.find("no manifest here")
  end
end
