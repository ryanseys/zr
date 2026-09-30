# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/store"

# The one content store of zr's caches (lib/zr/store.rb).
class StoreTest < Minitest::Test
  Store = Zr::Store

  def setup
    @dir = Dir.mktmpdir("zr-store-")
    @was = Zr::Paths.method(:cache)
    dir = @dir
    Zr::Paths.define_singleton_method(:cache) { dir }
  end

  def teardown
    Zr::Paths.define_singleton_method(:cache, @was)
    FileUtils.rm_rf(@dir)
  end

  def age(path, days) = File.utime(Time.now - (days * 86_400), Time.now - (days * 86_400), path)

  def test_a_key_is_the_digest_of_its_parts_each_ended_by_nul
    assert_equal Digest::SHA256.hexdigest("a\x001\x00"), Store.key("a", 1)
    refute_equal Store.key("ab", "c"), Store.key("a", "bc")
  end

  def test_an_entry_lies_under_its_kind_and_the_first_two_characters_of_its_key
    key = Store.key("x")

    assert_equal File.join(@dir, "store/object", key[0, 2], "#{key}.o"), Store.path(:object, key)
    assert_raises(ArgumentError) { Store.path(:object, "../etc") }
  end

  def test_each_codec_reads_back_what_it_wrote
    { raw: [:object, "\x00bytes".b], json: [:meta, { "a" => [1] }], marshal: [:unit, [:functions, { data: 1 }]] }.each do |codec, (kind, value)|
      key = Store.key(codec)
      Store.write(kind, key, value)

      assert_equal value, Store.read(kind, key), codec
    end
  end

  def test_a_missing_or_broken_entry_is_a_miss
    key = Store.key("broken")
    assert_nil Store.read(:unit, key)

    Zr::Paths.write_atomic(Store.path(:unit, key), "not marshal")
    assert_nil Store.read(:unit, key)
  end

  def test_get_builds_once_then_reads
    key = Store.key("fetch")
    built = 0

    2.times { assert_equal [1, 2], Store.get(:unit, key) { built += 1 and [1, 2] } }
    assert_equal 1, built
  end

  def test_a_directory_entry_is_filled_then_renamed
    key = Store.key("run")
    path = Store.write(:run, key) { |dir| File.write(File.join(dir, "program"), "bin") }

    assert_equal "bin", File.read(File.join(path, "program"))
    assert_equal path, Store.read(:run, key)
    assert_equal [path], Dir[File.join(File.dirname(path), "*")]
  end

  def test_once_builds_the_file_one_time
    key = Store.key("once")
    calls = 0
    2.times { Store.once(:object, key) { |path| calls += 1 and File.write(path, "o") } }

    assert_equal 1, calls
    assert_equal "o", Store.read(:object, key)
  end

  def test_a_write_after_a_source_moved_keeps_nothing
    was = Zr.method(:moved)
    Zr.define_singleton_method(:moved) { "lib/zr/lower.rb" }
    assert_raises(Zr::SourceChanged) { Store.write(:unit, Store.key("moved"), [1]) }
    Zr.define_singleton_method(:moved, was)
    assert_nil Store.read(:unit, Store.key("moved"))
  end

  def test_a_read_touches_an_old_entry
    key = Store.key("old")
    path = Store.write(:unit, key, 1)
    age(path, 3)

    Store.read(:unit, key)

    assert_operator File.mtime(path), :>, Time.now - 60
  end

  def test_eviction_removes_the_oldest_entries_that_no_root_names
    old, rooted, young = %w[old rooted young].map { |name| Store.key(name) }
    [old, rooted, young].each_with_index do |key, i|
      age(Store.write(:object, key, "x" * 1000), 10 - i)
    end
    Store.root("runtime", [Store.path(:object, rooted)])

    removed = Store.evict(limit: 2500)

    assert_equal [old], removed.map(&:key)
    assert_equal [rooted, young].sort, Store.entries.map(&:key).sort
  end

  def test_a_stale_root_protects_nothing
    key = Store.key("stale")
    Store.write(:object, key, "x")
    Store.root("gone", [Store.path(:object, key)])
    age(File.join(@dir, "store/roots/gone"), Store::ROOT_DAYS + 1)

    assert_equal [key], Store.clean.map(&:key)
  end

  def test_a_kind_over_its_quota_loses_its_oldest_entries
    Zr::Config.with(ZR_TEST_BINARIES_GB: (1500.0 / (1 << 30)).to_s) do
      first, second = %w[first second].map { |name| Store.key(name) }
      age(Store.write(:binary, first, "x" * 1000), 2)
      Store.write(:binary, second, "x" * 1000)

      assert_equal [first], Store.evict.map(&:key)
    end
  end

  def test_clean_keeps_rooted_entries_and_clear_removes_all
    kept, gone = %w[kept gone].map { |name| Store.key(name) }
    Store.write(:meta, kept, {})
    Store.write(:meta, gone, {})
    Store.root("build", [Store.path(:meta, kept)])

    assert_equal [gone], Store.clean.map(&:key)
    Store.clear
    refute File.exist?(Store.dir)
  end

  def test_clean_removes_a_lock_whose_entry_is_gone
    kept, gone = %w[kept gone].map { |name| Store.key(name) }
    Store.once(:object, kept) { |path| File.write(path, "o") }
    Store.once(:object, gone) { |path| File.write(path, "o") }
    Store.root("build", [Store.path(:object, kept)])

    Store.clean

    assert File.exist?("#{Store.path(:object, kept)}.lock")
    refute File.exist?("#{Store.path(:object, gone)}.lock")
  end
end
