# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/reach"

# Tests how `zr-dev test --changed` maps changed files to test paths
# (tool/lib/zr/dev/reach.rb).
class ReachTest < Minitest::Test
  Reach = Zr::Dev::Reach

  def test_a_changed_test_file_runs_itself
    program = "test/programs/core/comparable/comparison/a_base_class_that_calls_a_name_only_its_descendants_write_ty.rb"
    tests = Reach.tests(["test/unit/fork_pool_test.rb", "#{program}.expected"])

    assert_equal [program, "test/unit/fork_pool_test.rb"], tests
  end

  def test_a_deleted_test_file_runs_nothing
    assert_equal [], Reach.tests(%w[test/unit/no_such_file_test.rb])
  end

  def test_a_compiler_change_reaches_everything
    assert_equal :all, Reach.tests(%w[lib/zr/lower/function.rb])
    assert_equal :all, Reach.tests(%w[lib/zr/obj/macho/prelink.rb]), "a linker"
  end

  def test_a_driver_change_reaches_the_tests_that_load_it
    tests = Reach.tests(%w[lib/zr/cache/run.rb])

    assert_includes tests, "test/unit/run_cache_test.rb"
    refute_includes tests, "test/unit/bytes_test.rb"
    assert_includes tests, "test/programs/cli", "exe/zr loads it"
  end

  def test_the_load_graph_follows_literal_requires
    graph = Reach::LoadGraph.new
    test = File.join(Zr::Dev::ROOT, "test/unit/run_cache_test.rb")

    assert graph.reaches?(test, File.join(Zr::Dev::ROOT, "lib/zr/cache/run.rb"))
    assert graph.reaches?(test, File.join(Zr::Dev::ROOT, "test/test_helper.rb"))
    refute graph.reaches?(test, File.join(Zr::Dev::ROOT, "lib/zr/doctor.rb"))
  end

  # A program's files can be a link to a tree below test/fixtures/programs
  # that other programs share; a change there reaches each of them.
  def test_a_change_below_a_shared_fixture_reaches_the_programs_that_link_it
    tests = Reach.tests(["test/fixtures/programs/securerandom/stdlib/securerandom/securerandom.rb"])

    assert_equal 6, tests.size
    assert(tests.all? { |path| path.start_with?("test/programs/stdlib/securerandom/") && path.end_with?(".rb") })
  end

  def test_a_doc_change_reaches_nothing
    assert_equal [], Reach.tests(%w[docs/README.md])
  end

  def test_a_tool_change_reaches_the_unit_tests
    assert_equal ["test/unit"], Reach.tests(%w[tool/bench.rb])
  end

  def test_a_file_of_an_os_layer_maps_as_its_name
    assert_equal Reach.core("errno"), Reach.tests(%w[lib/zr/runtime/core/os/darwin/errno.rb])
  end

  # `zr-dev test` joins each path to the root, so each one is below it.
  def test_each_path_is_below_the_root
    tests = Reach.tests(%w[lib/zr/runtime/core/gc.rb lib/zr/runtime/ext/etc.so.rb tool/bench.rb test/unit/fork_pool_test.rb])

    refute_empty tests
    tests.each { |path| assert_path_exists Zr::Dev.path(path), path }
  end
end
