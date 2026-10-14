# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/cache/unit"
require_relative "../../lib/zr/cache/parse"
require_relative "../support/binaries"

# A cache key contains the digest of the sources that a build read. If a
# source changes while the build runs, what the build makes after that
# is a mix of two trees. A cache then returns that mix for the key until
# the source changes again. Thus a runtime records the file stamp (mtime and size) of
# every file that its digest covers, and each cache write first checks
# whether one of them has changed.
class SourceChangedTest < Minitest::Test
  def setup
    @runtime = Zr::Runtime.for
    @runtime.digest
    @file = File.join(Dir.mktmpdir("zr-moved-"), "source.rb")
    File.write(@file, "1\n")
  end

  def teardown
    stamps.delete(@file)
    FileUtils.rm_rf(File.dirname(@file))
  end

  def stamps = @runtime.instance_variable_get(:@stamps)

  def watching
    stamps[@file] = Zr::Paths.stamp(@file)
    yield
  end

  def test_source_change_is_nil_when_files_are_unchanged
    assert_nil Zr::SourceGuard.changed_file
    watching { assert_nil Zr::SourceGuard.changed_file }
  end

  def test_source_change_returns_a_rewritten_file
    watching do
      File.write(@file, "12\n")
      assert_equal @file, Zr::SourceGuard.changed_file
      assert_equal @file, @runtime.moved
    end
  end

  def test_source_change_returns_a_deleted_file
    watching do
      File.delete(@file)
      assert_equal @file, Zr::SourceGuard.changed_file
    end
  end

  def test_cache_writes_raise_when_a_source_changed
    watching do
      File.write(@file, "12\n")
      error = assert_raises(Zr::SourceChanged) { Zr::SourceGuard.check! }
      assert_includes error.message, @file
      assert_raises(Zr::SourceChanged) { Zr::Cache::Store.write_file(File.join(Zr::Paths.cache, "moved-probe"), "x") }
      assert_raises(Zr::SourceChanged) { Zr::Cache::Parse.keep(:derived, "moved-probe", "x") }
      cache = Zr::Cache::Unit.new(runtime: "r", traced: 0, entries: [])
      unit = Zr::Hir::Unit.new("probe.rb", [], nil, [], false, nil, false, "1", false)
      assert_raises(Zr::SourceChanged) { cache.keep(cache.key(unit, "zr_toplevel"), [], []) }
      assert_raises(Zr::SourceChanged) { Zr::Test::Binaries.keep(File.join(Zr::Paths.cache, "moved-probe"), @file, nil, "/nowhere") }
    end
    refute_path_exists File.join(Zr::Paths.cache, "moved-probe")
  end
end
