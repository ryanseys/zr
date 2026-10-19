# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/cache/janitor"

# An installed zr cleans its own cache once it grows past
# ZR_CACHE_MAX_GB (lib/zr/cache/janitor.rb). A checkout never does.
class CacheTest < Minitest::Test
  # A cache with one old entry of the store, 2 MB, unused for 3 days.
  def with_cache(limit_gb)
    Dir.mktmpdir("zr-cache-") do |dir|
      Zr::Config.with(ZR_CACHE_MAX_GB: limit_gb) do
        Zr::Session.current.set(:cache, dir)
        old = Zr::Cache::Store.write(:object, "0" * 64, "x" * (2 << 20))
        File.utime(Time.now - (3 * 86_400), Time.now - (3 * 86_400), old)
        yield dir, old
      ensure
        Zr::Session.current.forget(:cache)
      end
    end
  end

  def test_an_installed_zr_over_the_limit_deletes_what_it_does_not_use
    with_cache("0.001") do |_dir, old|
      stub_method(Zr::Paths, :checkout?, false) { Zr::Cache::Janitor.trim }

      refute_path_exists old
    end
  end

  def test_a_cache_under_the_limit_keeps_its_files
    with_cache("5") do |_dir, old|
      stub_method(Zr::Paths, :checkout?, false) { Zr::Cache::Janitor.trim }

      assert_path_exists old
    end
  end

  def test_a_checkout_never_trims
    with_cache("0.001") do |_dir, old|
      stub_method(Zr::Paths, :checkout?, true) { Zr::Cache::Janitor.trim }

      assert_path_exists old
    end
  end

  def test_the_cache_is_measured_at_most_once_a_day
    with_cache("5") do |dir, old|
      stub_method(Zr::Paths, :checkout?, false) do
        Zr::Cache::Janitor.trim
        Zr::Config.with(ZR_CACHE_MAX_GB: "0.001") { Zr::Cache::Janitor.trim }
      end

      assert_path_exists old
      assert_path_exists File.join(dir, ".measured")
    end
  end
  def test_a_rooted_entry_stays_over_the_limit
    with_cache("0.001") do |_dir, old|
      Zr::Cache::Store.root("build", [old])
      stub_method(Zr::Paths, :checkout?, false) { Zr::Cache::Janitor.trim }

      assert_path_exists old
    end
  end

  # A clean deletes the store's unused entries, and names the kind of each.
  def test_a_clean_removes_unused_entries
    with_cache("5") do |dir, old|
      gone = Zr::Cache::Janitor.prune

      assert_includes gone, old
      assert_equal "object", Zr::Cache::Janitor.kind(Zr::Cache::Store.path(:object, "1" * 64))
      assert_nil Zr::Cache::Janitor.kind(File.join(dir, "elsewhere"))
    end
  end
end
