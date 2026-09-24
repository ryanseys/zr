# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/paths"

# The compiler's own directory helpers, which stand in for fileutils and
# tmpdir so a compiled compiler never loads them.
class PathsTest < Minitest::Test
  def test_a_scratch_directory_is_named_as_mktmpdir_names_one_and_removed_after
    kept = nil
    Zr::Paths.tmpdir("zr-paths-") do |dir|
      kept = dir
      assert File.directory?(dir)
      assert_equal 0o700, File.stat(dir).mode & 0o777
      assert_match(/\Azr-paths-\d{8}-#{Process.pid}-[0-9a-z]+\z/, File.basename(dir))
      Zr::Paths.mkdir_p(File.join(dir, "a/b/c"))
      File.write(File.join(dir, "a/b/c/file"), "x")
      File.symlink("/", File.join(dir, "a/root"))
    end
    refute File.exist?(kept)
  end

  def test_a_scratch_directory_is_removed_when_the_block_raises
    kept = nil
    assert_raises(RuntimeError) { Zr::Paths.tmpdir("zr-paths-") { |dir| kept = dir; raise "no" } }
    refute File.exist?(kept)
  end

  def test_mkdir_p_leaves_a_directory_that_is_there
    Zr::Paths.tmpdir("zr-paths-") do |dir|
      Zr::Paths.mkdir_p(dir)
      Zr::Paths.mkdir_p(File.join(dir, "x"))
      Zr::Paths.mkdir_p(File.join(dir, "x"))
      assert File.directory?(File.join(dir, "x"))
      File.write(File.join(dir, "f"), "")
      assert_raises(Errno::EEXIST) { Zr::Paths.mkdir_p(File.join(dir, "f")) }
    end
  end

  # A build under a path root (`--path-root`) writes a path below zr's
  # root or below the directory it runs in as the root plus the rest.
  def test_a_path_root_writes_paths_below_the_gem_and_the_build_directory_under_it
    Zr::Paths.tmpdir("zr-paths-") do |dir|
      Dir.chdir(dir) do
        Zr::Paths.root = "/src/"
        here = Dir.pwd
        assert_equal "/src/runtime/core/string.rb", Zr::Paths.shown(File.join(Zr::Paths::ROOT, "runtime/core/string.rb"))
        assert_equal "/src/lib/a.rb", Zr::Paths.shown(File.join(here, "lib/a.rb"))
        assert_equal "/src", Zr::Paths.shown(here)
        assert_equal "/elsewhere/a.rb", Zr::Paths.shown("/elsewhere/a.rb")
        assert_equal "#{here}x/a.rb", Zr::Paths.shown("#{here}x/a.rb")
        assert_equal "a.rb", Zr::Paths.shown("a.rb")
        assert_equal "<internal:gem_prelude>", Zr::Paths.shown("<internal:gem_prelude>")
        Zr::Paths.root = "/"
        assert_equal "/lib/a.rb", Zr::Paths.shown(File.join(here, "lib/a.rb"))
        assert_equal "/", Zr::Paths.shown(here)
      end
    end
  ensure
    Zr::Paths.root = nil
  end

  def test_no_path_root_writes_each_path_as_it_is
    Zr::Paths.root = nil
    path = File.join(Zr::Paths::ROOT, "runtime/core/string.rb")
    assert_same path, Zr::Paths.shown(path)
  end

  # The longer of the two directories wins, so a gem inside the build
  # directory writes its files below the root as a gem outside it does.
  def test_the_longer_directory_is_the_one_a_path_is_written_below
    Dir.chdir(File.dirname(Zr::Paths::ROOT)) do
      Zr::Paths.root = "/src"
      assert_equal "/src/runtime/core/string.rb", Zr::Paths.shown(File.join(Zr::Paths::ROOT, "runtime/core/string.rb"))
    end
  ensure
    Zr::Paths.root = nil
  end
end
