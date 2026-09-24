# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/zr"
require_relative "../../lib/zr/unit_cache"
require_relative "../../lib/zr/parse_cache"
require_relative "../support/binaries"

# A cache key names the digest of the sources a build read; a source
# edited while the build runs makes what the build builds after that a
# mix of two trees, and a cache would answer for the key with it until
# the source moved again (the spec tier once kept three hundred such
# binaries). So a runtime remembers the stat of every file its digest
# covers, and every cache write asks first whether one has moved.
class MovedTest < Minitest::Test
  def setup
    @runtime = Zr::Zr.runtime
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
    stamps[@file] = Zr::Zr.stamp_of(@file)
    yield
  end

  def test_nothing_has_moved_while_the_sources_stand
    assert_nil Zr::Zr.moved
    watching { assert_nil Zr::Zr.moved }
  end

  def test_a_source_rewritten_is_the_one_that_moved
    watching do
      File.write(@file, "12\n")
      assert_equal @file, Zr::Zr.moved
      assert_equal @file, @runtime.moved
    end
  end

  def test_a_source_gone_is_the_one_that_moved
    watching do
      File.delete(@file)
      assert_equal @file, Zr::Zr.moved
    end
  end

  def test_no_cache_takes_a_write_while_a_source_has_moved
    watching do
      File.write(@file, "12\n")
      error = assert_raises(Zr::Zr::Moved) { Zr::Zr.settled! }
      assert_includes error.message, @file
      assert_raises(Zr::Zr::Moved) { Zr::Zr.write_cache(File.join(Zr::Zr.cache, "moved-probe"), "x") }
      assert_raises(Zr::Zr::Moved) { Zr::ParseCache.write(File.join(Zr::Zr.cache, "moved-probe"), "x") }
      cache = Zr::UnitCache.new(dir: Zr::Zr.cache, runtime: "r", table: "t", traced: 0, entries: [])
      unit = Zr::Hir::Unit.new("probe.rb", [], nil, [], false, nil, false, "1", false)
      assert_raises(Zr::Zr::Moved) { cache.keep(unit, "zr_toplevel", [], []) }
      assert_raises(Zr::Zr::Moved) { Zr::Spec::Binaries.keep(File.join(Zr::Zr.cache, "moved-probe"), @file, nil, "/nowhere") }
    end
    refute File.exist?(File.join(Zr::Zr.cache, "moved-probe"))
  end
end
