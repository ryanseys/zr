# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/paths"

# The compiler's own directory helpers, which stand in for fileutils and
# tmpdir so a compiled compiler never loads them.
class PathsTest < Minitest::Test
  def test_a_scratch_directory_is_named_as_mktmpdir_names_one_and_removed_after
    kept = nil
    Ze0::Paths.scratch("ze0-paths-") do |dir|
      kept = dir
      assert File.directory?(dir)
      assert_equal 0o700, File.stat(dir).mode & 0o777
      assert_match(/\Aze0-paths-\d{8}-#{Process.pid}-[0-9a-z]+\z/, File.basename(dir))
      Ze0::Paths.mkdir_p(File.join(dir, "a/b/c"))
      File.write(File.join(dir, "a/b/c/file"), "x")
      File.symlink("/", File.join(dir, "a/root"))
    end
    refute File.exist?(kept)
  end

  def test_a_scratch_directory_is_removed_when_the_block_raises
    kept = nil
    assert_raises(RuntimeError) { Ze0::Paths.scratch("ze0-paths-") { |dir| kept = dir; raise "no" } }
    refute File.exist?(kept)
  end

  def test_mkdir_p_leaves_a_directory_that_is_there
    Ze0::Paths.scratch("ze0-paths-") do |dir|
      Ze0::Paths.mkdir_p(dir)
      Ze0::Paths.mkdir_p(File.join(dir, "x"))
      Ze0::Paths.mkdir_p(File.join(dir, "x"))
      assert File.directory?(File.join(dir, "x"))
      File.write(File.join(dir, "f"), "")
      assert_raises(Errno::EEXIST) { Ze0::Paths.mkdir_p(File.join(dir, "f")) }
    end
  end
end
