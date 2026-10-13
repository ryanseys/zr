# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../support/result_cache"

# Tests what the key of the host result cache holds
# (test/support/result_cache.rb): a pass stays only while nothing that a
# run reads changed.
class ResultCacheTest < Minitest::Test
  ResultCache = Zr::Test::ResultCache

  def test_each_change_to_the_checkout_outside_the_programs_misses
    in_checkout do |root|
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "tool/hosted.rb"), "# a change to the walker\n")
      edited = ResultCache.new(root: root).tree

      refute_equal digest, edited, "a change that git does not have yet"
      assert_equal edited, ResultCache.new(root: root).tree, "no change since: the same digest"
      git(root, "add", "tool/hosted.rb")

      refute_equal digest, ResultCache.new(root: root).tree, "a staged change"
      staged = ResultCache.new(root: root).tree
      File.write(File.join(root, "Gemfile.lock"), "GEM\n")

      refute_equal staged, ResultCache.new(root: root).tree, "a new file"
    end
  end

  def test_a_change_below_the_programs_leaves_the_others_their_passes
    in_checkout do |root|
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "test/programs/core/new.rb"), "p 2\n")
      File.write(File.join(root, "test/programs/core/x.rb"), "p 3\n")

      assert_equal digest, ResultCache.new(root: root).tree
    end
  end

  def test_a_copy_that_is_no_checkout_stamps_its_files
    Dir.mktmpdir("zr-result-cache-") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/a.rb"), "1\n")
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "lib/a.rb"), "22\n")

      refute_equal digest, ResultCache.new(root: root).tree
    end
  end

  def test_the_variables_that_can_change_a_run_are_in_the_key
    pairs = { "ZR_LINKER" => "ruby", "RUBYOPT" => "-W0", "ZR_PROGRAMS" => "core/gc", "ZR_TEST_FRESH" => "1", "MT_CPU" => "3" }
    with_env(pairs) do
      names = ResultCache.variables.map(&:first)

      assert_includes names, "ZR_LINKER"
      assert_includes names, "RUBYOPT"
      refute_includes names, "ZR_PROGRAMS", "it picks tests"
      refute_includes names, "ZR_TEST_FRESH", "it picks tests"
      refute_includes names, "MT_CPU", "the worker count changes no result"
    end
  end

  private

  # A git checkout with a tracked file in tool/ and one program.
  def in_checkout
    Dir.mktmpdir("zr-result-cache-") do |root|
      FileUtils.mkdir_p(File.join(root, "tool"))
      FileUtils.mkdir_p(File.join(root, "test/programs/core"))
      File.write(File.join(root, "tool/hosted.rb"), "# the walker\n")
      File.write(File.join(root, "test/programs/core/x.rb"), "p 1\n")
      git(root, "init", "-q")
      git(root, "add", ".")
      git(root, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "start")
      yield root
    end
  end

  def git(root, *args)
    assert system("git", "-C", root, *args, out: File::NULL, err: File::NULL), "git #{args.join(" ")}"
  end
end
