# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/affected"

# Tests how `zr-dev affected` maps changed files to test paths, and the
# bin/minitest command that runs them (tool/affected.rb).
class AffectedTest < Minitest::Test
  def affected = Zr::Dev::Commands::Affected.new("affected")

  def test_the_command_runs_unit_files_by_path_and_programs_by_zr_programs
    env, _ruby, minitest, *paths = Zr::Dev::Commands::Affected.command(%w[test/unit/fork_pool_test.rb test/programs/core/gc test/programs/cli])

    assert minitest.end_with?("bin/minitest")
    assert_equal %w[test/unit/fork_pool_test.rb test/programs_test.rb], paths
    assert_equal({ "ZR_PROGRAMS" => "core/gc,cli" }, env)
  end

  def test_a_command_of_unit_files_alone_sets_nothing
    env, _ruby, _minitest, *paths = Zr::Dev::Commands::Affected.command(%w[test/unit/fork_pool_test.rb])

    assert_empty env
    assert_equal %w[test/unit/fork_pool_test.rb], paths
  end

  def test_a_changed_test_file_runs_itself
    program = "test/programs/core/comparable/comparison/a_base_class_that_calls_a_name_only_its_descendants_write_ty.rb"
    plan = affected.plan(["test/unit/fork_pool_test.rb", "#{program}.expected"])

    assert_equal [program, "test/unit/fork_pool_test.rb"], plan
  end

  def test_a_deleted_test_file_runs_nothing
    assert_equal [], affected.plan(%w[test/unit/no_such_file_test.rb])
  end

  def test_a_compiler_change_reaches_everything
    assert_equal :all, affected.plan(%w[lib/zr/lower/function.rb])
    assert_equal :all, affected.plan(%w[lib/zr/obj/macho/prelink.rb]), "a linker"
  end

  def test_a_driver_change_reaches_the_tests_that_load_it
    plan = affected.plan(%w[lib/zr/cache/run.rb])

    assert_includes plan, "test/unit/run_cache_test.rb"
    refute_includes plan, "test/unit/bytes_test.rb"
    assert_includes plan, "test/programs/cli", "exe/zr loads it"
  end

  def test_the_load_graph_follows_literal_requires
    graph = Zr::Dev::Commands::Affected::LoadGraph.new
    test = File.join(Zr::Dev::ROOT, "test/unit/run_cache_test.rb")

    assert graph.reaches?(test, File.join(Zr::Dev::ROOT, "lib/zr/cache/run.rb"))
    assert graph.reaches?(test, File.join(Zr::Dev::ROOT, "test/test_helper.rb"))
    refute graph.reaches?(test, File.join(Zr::Dev::ROOT, "lib/zr/doctor.rb"))
  end

  # A program's files can be a link to a tree below test/fixtures/programs
  # that other programs share; a change there reaches each of them.
  def test_a_change_below_a_shared_fixture_reaches_the_programs_that_link_it
    plan = affected.plan(["test/fixtures/programs/securerandom/stdlib/securerandom/securerandom.rb"])

    assert_equal 6, plan.size
    assert(plan.all? { |path| path.start_with?("test/programs/stdlib/securerandom/") && path.end_with?(".rb") })
  end

  def test_a_doc_change_reaches_nothing
    assert_equal [], affected.plan(%w[docs/README.md])
  end

  def test_a_tool_change_reaches_the_unit_tests
    assert_equal [File.join(Zr::Dev::ROOT, "test/unit")], affected.plan(%w[tool/bench.rb])
  end

  def test_a_file_of_an_os_layer_maps_as_its_name
    assert_equal affected.core("errno"), affected.plan(%w[lib/zr/runtime/core/os/darwin/errno.rb])
  end
end
