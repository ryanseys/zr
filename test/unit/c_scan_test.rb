# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../tool/lib/zr/dev/gems"
require_relative "../../tool/gems"
require_relative "../../tool/gems/sweep"

# Tests Gems::CScan (tool/lib/zr/dev/gems/c_scan.rb): it compiles a
# gem's C with no gem code and lists what zr's C API lacks of its
# imports. Each test writes a small gem with C in a temporary directory
# and compiles it with the host's cc.
class CScanTest < Minitest::Test
  Gems = Zr::Dev::Gems

  # A function that no ruby has, so the C API lacks it.
  UNKNOWN = "rb_zr_scan_test_unknown"

  MAIN = <<~C.freeze
    #include "ruby.h"
    #include "extconf.h"
    #include "shared.h"
    extern VALUE #{UNKNOWN}(VALUE);
    static VALUE twice(VALUE self, VALUE x) { return #{UNKNOWN}(rb_funcall(x, rb_intern("*"), 1, INT2FIX(SHARED))); }
    void Init_scanned(void) { rb_define_method(rb_cObject, "twice", twice, 1); }
  C

  # A file that does not compile.
  BROKEN = "int broken( {\n"

  def setup
    skip "no cc" unless system("cc", "--version", out: File::NULL, err: File::NULL)
    @dir = Dir.mktmpdir("zr-c-scan-")
    @scanner = Gems::CScan.new(dir: File.join(@dir, "capi"))
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_a_scan_lists_the_ruby_imports_and_what_the_c_api_lacks
    scan = @scanner.call(gem("scanned", "main.c" => MAIN))

    assert_predicate scan, :complete?
    assert_equal [1, 1, nil], [scan.sources, scan.compiled, scan.error]
    assert_includes scan.imports, "rb_define_method"
    assert_includes scan.imports, "rb_funcall"
    assert_equal [UNKNOWN], scan.missing
    refute(scan.imports.any? { |name| name.start_with?("_") || !Zr::Ext::CApi.ruby?(name) }, "only ruby's names, without the underscore")
  end

  def test_a_file_that_does_not_compile_leaves_the_others
    scan = @scanner.call(gem("scanned", "main.c" => MAIN, "broken.c" => BROKEN))

    refute_predicate scan, :complete?
    assert_equal [2, 1], [scan.sources, scan.compiled]
    assert_match(/\Abroken\.c: .*error/, scan.error)
    assert_equal [UNKNOWN], scan.missing
  end

  def test_a_scan_runs_no_gem_code
    marker = File.join(@dir, "ran")
    subject = gem("scanned", "main.c" => MAIN, "extconf.rb" => "File.write(#{marker.dump}, 'ran')\n")

    @scanner.call(subject)

    refute_path_exists marker
  end

  def test_a_scan_is_kept_and_its_missing_names_are_found_again
    subject = gem("scanned", "main.c" => MAIN)
    first = @scanner.call(subject)
    FileUtils.rm_rf(subject.root)

    kept = @scanner.call(subject)

    assert_equal first, kept
    assert_equal [UNKNOWN], kept.missing
  end

  def test_only_the_c_extensions_that_zr_does_not_port_are_scanned
    c = gem("scanned", "main.c" => MAIN)
    ported = gem("json", "main.c" => MAIN)
    plain = Gems::Subject.new(name: "plain", version: "1.0", root: @dir, require_paths: ["lib"], extensions: [],
                              dependencies: [], source: "path")

    assert_equal ["scanned"], @scanner.natives([plain, ported, c]).map(&:gem)
  end

  def test_the_ranking_counts_the_swept_gems_that_wait_on_each_function
    scan = ->(gem, missing) { Gems::CScan::Scan.new(gem: gem, version: "1.0", sources: 1, compiled: 1, imports: missing, error: nil) }
    a = scan.call("ext-a", %w[rb_zr_one rb_zr_two])
    b = scan.call("ext-b", %w[rb_zr_two])

    ranking = Gems::CScan.rank([["app", [a, b]], ["lib", [b]], ["web", [b]], ["plain", []]])

    assert_equal [["rb_zr_two", %w[app lib web]], ["rb_zr_one", %w[app]]], ranking.functions
    assert_equal [["ext-b", %w[app lib web]], ["ext-a", %w[app]]], ranking.extensions.map { |gem, users, _| [gem, users] }
  end

  def test_a_c_scan_sweep_writes_a_row_for_each_gem_and_the_ranking
    sweep = Zr::Dev::GemCompat::Sweep.new("gems sweep")
    scans = { "app" => [@scanner.call(gem("scanned", "main.c" => MAIN))], "plain" => [] }
    trial = Object.new
    trial.define_singleton_method(:scan) { |request| [request.name, scans.fetch(request.name)] }
    sweep.define_singleton_method(:trial) { trial }
    sweep.instance_variable_set(:@c_scan, true)
    capi = StringIO.new
    lines = []

    rows = sweep.c_scan(%w[app plain].map { Gems::Request.parse(_1) }, capi, ->(line) { lines << line })
    sweep.rank(rows.map { |row| [row.name, row.scans] }, File.join(@dir, "capi.txt"), ->(line) { lines << line })

    written = capi.string.lines.map { |line| JSON.parse(line) }
    assert_equal [["app", [[UNKNOWN]]], ["plain", []]], written.map { |row| [row["name"], row["scans"].map { _1["missing"] }] }
    assert_match(/\A\[1\/2\] C +app  C: scanned lacks 1 /, lines[0])
    assert_match(/\A\[2\/2\] no C +plain /, lines[1])
    assert_match(/^ +1  #{UNKNOWN} +app$/o, File.read(File.join(@dir, "capi.txt")))
  end

  private

  # A gem named `name` whose extension is ext/<name>/extconf.rb, with
  # `files` beside it, and a header in another directory below ext/.
  def gem(name, files)
    root = File.join(@dir, "gems", "#{name}-1.0")
    ext = File.join(root, "ext", name)
    FileUtils.mkdir_p([ext, File.join(root, "ext", "include")])
    File.write(File.join(root, "ext", "include", "shared.h"), "#define SHARED 2\n")
    files.each { |file, text| File.write(File.join(ext, file), text) }
    Gems::Subject.new(name: name, version: "1.0", root: root, require_paths: ["lib"], extensions: ["ext/#{name}/extconf.rb"],
                      dependencies: [], source: "path")
  end
end
