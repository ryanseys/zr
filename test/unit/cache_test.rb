# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/cache"

# An installed zr cleans its own cache once it grows past
# ZR_CACHE_MAX_GB (lib/zr/cache.rb). A checkout never does.
class CacheTest < Minitest::Test
  # Replaces a module method for the block, then puts it back.
  def swap(owner, name, value)
    was = owner.method(name)
    owner.define_singleton_method(name) { |*| value }
    yield
  ensure
    owner.define_singleton_method(name, was)
  end

  # A cache with one old entry of the store, 2 MB, unused for 3 days.
  def with_cache(limit_gb)
    Dir.mktmpdir("zr-cache-") do |dir|
      Zr::Config.with(ZR_CACHE_MAX_GB: limit_gb) do
        swap(Zr::Paths, :cache, dir) do
          old = Zr::Store.write(:object, "0" * 64, "x" * (2 << 20))
          File.utime(Time.now - (3 * 86_400), Time.now - (3 * 86_400), old)
          swap(Zr::Cache, :other_compilers, []) { yield dir, old }
        end
      end
    end
  end

  def test_an_installed_zr_over_the_limit_deletes_what_it_does_not_use
    with_cache("0.001") do |_dir, old|
      swap(Zr::Paths, :checkout?, false) { Zr::Cache.trim }

      refute File.exist?(old)
    end
  end

  def test_a_cache_under_the_limit_keeps_its_files
    with_cache("5") do |_dir, old|
      swap(Zr::Paths, :checkout?, false) { Zr::Cache.trim }

      assert File.exist?(old)
    end
  end

  def test_a_checkout_never_trims
    with_cache("0.001") do |_dir, old|
      swap(Zr::Paths, :checkout?, true) { Zr::Cache.trim }

      assert File.exist?(old)
    end
  end

  def test_the_cache_is_measured_at_most_once_a_day
    with_cache("5") do |dir, old|
      swap(Zr::Paths, :checkout?, false) do
        Zr::Cache.trim
        Zr::Config.with(ZR_CACHE_MAX_GB: "0.001") { Zr::Cache.trim }
      end

      assert File.exist?(old)
      assert File.exist?(File.join(dir, ".measured"))
    end
  end
  def test_a_rooted_entry_stays_over_the_limit
    with_cache("0.001") do |_dir, old|
      Zr::Store.root("build", [old])
      swap(Zr::Paths, :checkout?, false) { Zr::Cache.trim }

      assert File.exist?(old)
    end
  end

  # The files of a zr from before the store are never read again.
  def test_a_clean_removes_the_old_layout_and_keeps_the_harness_marks
    with_cache("5") do |dir, _old|
      old_layout = [File.join(dir, "runtime-#{"1" * 64}.o"), File.join(dir, "parse/ab.marshal")]
      mark = File.join(dir, "built-#{"2" * 64}.ok")
      [*old_layout, mark].each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "x")
      end

      gone = Zr::Cache.prune

      assert_empty old_layout.select { |path| File.exist?(path) }
      assert File.exist?(mark)
      refute File.exist?(File.join(dir, "parse"))
      assert_equal "old layout", Zr::Cache.kind(old_layout.first)
      assert_equal "object", Zr::Cache.kind(Zr::Store.path(:object, "1" * 64))
      assert_includes gone, old_layout.first
    end
  end
end
