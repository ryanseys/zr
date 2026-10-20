# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../support/result_cache"

# Tests what the key of the result cache holds
# (test/support/result_cache.rb): a pass stays only while nothing that a
# run reads changed.
class ResultCacheTest < Minitest::Test
  ResultCache = Zr::Test::ResultCache

  def test_each_change_to_the_checkout_outside_the_programs_misses
    in_checkout do |root|
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "tool/expect.rb"), "# a change to the recorder\n")
      edited = ResultCache.new(root: root).tree

      refute_equal digest, edited, "a change that git does not have yet"
      assert_equal edited, ResultCache.new(root: root).tree, "no change since: the same digest"
      git(root, "add", "tool/expect.rb")

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

  # The docs, the unit and ext tests and the Markdown files at the top
  # are no input of a program test, so a change to them keeps each pass.
  # A Markdown file below lib/ or vendor/ is: a program can read it.
  def test_a_change_that_no_program_reads_leaves_each_pass
    in_checkout(%w[docs/guide.md test/unit/a_test.rb test/ext/b_test.rb README.md lib/notes.md]) do |root|
      digest = ResultCache.new(root: root).tree
      %w[docs/guide.md test/unit/a_test.rb test/ext/b_test.rb README.md docs/new.md].each do |rel|
        File.write(File.join(root, rel), "# changed\n")
      end
      git(root, "add", "README.md")

      assert_equal digest, ResultCache.new(root: root).tree
      File.write(File.join(root, "lib/notes.md"), "# changed\n")

      refute_equal digest, ResultCache.new(root: root).tree, "a Markdown file below lib/"
    end
  end

  # A tool that no program test loads (zr-dev bench) is no input, so an
  # edit to it keeps each pass; an edit to lib/ misses.
  def test_an_edit_to_a_tool_keeps_each_pass_and_an_edit_to_lib_does_not
    in_checkout(%w[tool/bench.rb lib/zr.rb]) do |root|
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "tool/bench.rb"), "# changed\n")

      assert_equal digest, ResultCache.new(root: root).tree
      File.write(File.join(root, "lib/zr.rb"), "# changed\n")

      refute_equal digest, ResultCache.new(root: root).tree
    end
  end

# READ names the program tests' harness from its load graph, so a new
# support file joins the key with no list to edit.
def test_the_key_holds_the_harness_that_a_program_test_loads
  %w[test/programs_test.rb test/test_helper.rb test/support/result_cache.rb test/support/shard.rb
     tool/lib/zr/dev/reach.rb].each { |rel| assert_includes ResultCache::READ, rel }
  assert ResultCache::HARNESS.none? { |rel| rel.start_with?("/", "lib/", "vendor/") }, ResultCache::HARNESS.inspect
end

  def test_a_copy_that_is_no_checkout_leaves_out_the_other_test_tiers
    Dir.mktmpdir("zr-result-cache-") do |root|
      FileUtils.mkdir_p(File.join(root, "test/unit"))
      FileUtils.mkdir_p(File.join(root, "test/support"))
      File.write(File.join(root, "test/unit/a_test.rb"), "1\n")
      File.write(File.join(root, "test/support/programs.rb"), "1\n")
      digest = ResultCache.new(root: root).tree
      File.write(File.join(root, "test/unit/a_test.rb"), "22\n")

      assert_equal digest, ResultCache.new(root: root).tree
      File.write(File.join(root, "test/support/programs.rb"), "22\n")

      refute_equal digest, ResultCache.new(root: root).tree, "the test support is an input"
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
    pairs = { "ZR_LINKER" => "ruby", "RUBYOPT" => "-W0", "ZR_PROGRAMS" => "core/gc", "ZR_TEST_FRESH" => "1", "MT_CPU" => "3",
              "ZR_TEST_TMP" => "/tmp/x", "ZR_MINITEST_RUN" => "/tmp/x/run" }
    with_env(pairs) do
      names = ResultCache.variables.map(&:first)

      assert_includes names, "ZR_LINKER"
      assert_includes names, "RUBYOPT"
      refute_includes names, "ZR_PROGRAMS", "it picks tests"
      refute_includes names, "ZR_TEST_FRESH", "it picks tests"
      refute_includes names, "MT_CPU", "the worker count changes no result"
      refute_includes names, "ZR_TEST_TMP", "it moves the run files"
      refute_includes names, "ZR_MINITEST_RUN", "it names the run files"
    end
  end

  private

  # A git checkout with a tracked file in tool/, one program, and the
  # files `more` (paths below the root).
  def in_checkout(more = [])
    Dir.mktmpdir("zr-result-cache-") do |root|
      FileUtils.mkdir_p(File.join(root, "tool"))
      FileUtils.mkdir_p(File.join(root, "test/programs/core"))
      File.write(File.join(root, "tool/expect.rb"), "# the recorder\n")
      File.write(File.join(root, "test/programs/core/x.rb"), "p 1\n")
      more.each do |rel|
        FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
        File.write(File.join(root, rel), "# start\n")
      end
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
