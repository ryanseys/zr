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

  def with_cache(limit_gb)
    Dir.mktmpdir("zr-cache-") do |dir|
      old = File.join(dir, "runtime-#{"0" * 64}.o")
      File.binwrite(old, "x" * (2 << 20))
      File.utime(Time.now - (3 * 86_400), Time.now - (3 * 86_400), old)
      was = ENV.fetch("ZR_CACHE_MAX_GB", nil)
      ENV["ZR_CACHE_MAX_GB"] = limit_gb
      swap(Zr::Paths, :cache, dir) do
        swap(Zr::Cache, :live, []) do
          swap(Zr::Cache, :other_compilers, []) { yield dir, old }
        end
      end
    ensure
      ENV["ZR_CACHE_MAX_GB"] = was
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
        ENV["ZR_CACHE_MAX_GB"] = "0.001"
        Zr::Cache.trim
      end

      assert File.exist?(old)
      assert File.exist?(File.join(dir, ".measured"))
    end
  end
end
