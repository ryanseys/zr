# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/affected"

# Tests how `zr-dev affected` and `bin/test --changed` map changed files
# to test paths (tool/affected.rb).
class AffectedTest < Minitest::Test
  def affected = Zr::Dev::Affected.new("affected")

  def test_a_changed_test_file_runs_itself
    plan = affected.plan(%w[test/unit/fork_pool_test.rb test/spec/core/string/blocks_test.rb])

    assert_equal %w[test/spec/core/string/blocks_test.rb test/unit/fork_pool_test.rb], plan
  end

  def test_a_deleted_test_file_runs_nothing
    assert_equal [], affected.plan(%w[test/unit/no_such_file_test.rb])
  end

  def test_a_compiler_change_reaches_everything
    assert_equal :all, affected.plan(%w[lib/zr/cli.rb])
  end

  def test_a_doc_change_reaches_nothing
    assert_equal [], affected.plan(%w[docs/README.md])
  end

  def test_the_carried_description_reaches_everything
    assert_equal :all, affected.plan(%w[runtime/ext/os/darwin/zr_description.rb])
  end

  def test_a_tool_change_reaches_the_unit_tests
    assert_equal [File.join(Zr::Dev::ROOT, "test/unit")], affected.plan(%w[tool/edit.rb])
  end

  def test_a_file_of_an_os_layer_maps_as_its_name
    assert_equal affected.core("errno"), affected.plan(%w[runtime/core/os/darwin/errno.rb])
  end
end
