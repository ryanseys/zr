# frozen_string_literal: true

require "test_helper"
require_relative "../../.github/scripts/lanes"

# CI's lanes (.github/scripts/lanes.rb) come from Zr::Target::ALL and the
# `# zr-test:` comments of the unit files, so no workflow lists either.
class CiLanesTest < Minitest::Test
  def test_each_target_has_one_lane
    assert_equal Zr::Target::ALL.map(&:triple), Lanes.matrix.map { |lane| lane[:triple] }
  end

  # A unit file that no lane and no untagged run takes never runs in CI.
  def test_each_unit_file_runs_in_ci
    taken = Zr::Target::ALL.flat_map { |target| Lanes.units(target) } + Lanes.untagged

    assert_empty Lanes.files - taken, "name a kind of host that a lane is (`# zr-test: on KIND`, Needs::KINDS)"
  end

  def test_each_kind_that_a_file_names_is_one_that_some_lane_is
    Lanes.files.each do |file|
      Zr::Test::Needs.on(file).each do |kind|
        assert(Zr::Target::ALL.any? { |target| Zr::Test::Needs::KINDS.fetch(kind).call(target) }, "#{file}: #{kind}")
      end
    end
  end

  # A lane's tests build its host's runtime too (test/support/built.rb),
  # so a lane that runs on another target's host builds that runtime.
  def test_a_lane_builds_each_runtime_that_its_tests_read
    wasm = Lanes.matrix.find { |lane| lane[:triple] == Zr::Target::WASM32_WASI.triple }

    assert_equal 2, wasm[:builds].size
    assert(wasm[:builds].all? { |triple| Zr::Target.fetch(triple) })
  end

  # Only `checks` names files: the docs tests, which a docs-only pull
  # request runs with no lane.
  def test_a_lane_lists_no_unit_files
    named = File.read(File.join(ROOT, ".github/workflows/lane.yml")).scan(%r{test/unit/\w+_test\.rb})

    assert_empty named, "lane.yml takes its unit files from lanes.rb"
  end
end
