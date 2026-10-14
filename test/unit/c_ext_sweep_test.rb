# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../support/c_ext"

# tmp/test-ext keeps only what the C extension tests still use
# (test/support/c_ext.rb): a built extension that no run used for
# KEEP_DAYS goes, and so does the directory of a host whose ruby no longer
# runs the tests.
class CExtSweepTest < Minitest::Test
  CExt = Zr::Test::CExt
  NOW = Time.utc(2026, 10, 14, 12)

  def entry(root, rel, days_ago)
    path = File.join(root, rel)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "x.o"), "")
    at = NOW - (days_ago * CExt::DAY)
    File.utime(at, at, path)
    path
  end

  def test_the_sweep_keeps_what_a_run_used_and_removes_the_rest
    Dir.mktmpdir("zr-c-ext-sweep-") do |root|
      fresh = entry(root, "arm64-darwin27/aaaa", 2)
      stale = entry(root, "arm64-darwin27/bbbb", CExt::KEEP_DAYS + 1)
      gone_host = entry(root, "arm64-darwin23/cccc", 90)

      CExt.sweep(root, NOW)

      assert_path_exists fresh
      refute_path_exists stale
      refute_path_exists gone_host
      refute_path_exists File.dirname(gone_host), "a host directory with nothing left goes"
      assert_path_exists File.join(root, "arm64-darwin27")
    end
  end

  # A hit marks its directory once a day, so a used extension never ages
  # out, and most hits write nothing.
  def test_a_hit_marks_its_directory_at_most_once_a_day
    Dir.mktmpdir("zr-c-ext-sweep-") do |root|
      old = CExt::Built.new(dir: entry(root, "host/old", 3), bundle: "", object: "")
      new = CExt::Built.new(dir: entry(root, "host/new", 0.5), bundle: "", object: "")

      assert_same old, CExt.used(old, NOW)
      CExt.used(new, NOW)

      assert_equal NOW, File.mtime(old.dir)
      assert_equal NOW - (0.5 * CExt::DAY), File.mtime(new.dir)
    end
  end
end
