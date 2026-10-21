# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/release"

# `zr-dev release` (tool/release.rb): the decisions of a release, from
# texts that a test gives it.
class ReleaseCommandTest < Minitest::Test
  Release = Zr::Dev::Commands::Release

  CHANGELOG = <<~MD
    ## [Unreleased]

    ## [0.1.0] - 2026-11-02

    - A thing.
  MD
  VERSION_RB = %(module Zr\n  VERSION = "0.1.0"\nend\n)
  JOB = CIGate::JOB

  def test_a_dated_section_and_the_same_version_mean_the_bump_is_made
    assert Release.already_bumped?(CHANGELOG, VERSION_RB, "0.1.0")
  end

  def test_a_version_that_the_changelog_lacks_is_not_bumped
    refute Release.already_bumped?(CHANGELOG, VERSION_RB.sub("0.1.0", "0.2.0"), "0.2.0")
  end

  def test_a_version_rb_with_another_version_is_not_bumped
    refute Release.already_bumped?(CHANGELOG, VERSION_RB.sub("0.1.0", "0.0.9"), "0.1.0")
  end

  def test_left_out_gives_the_line_and_its_list
    body = "Notes.\n\nNot in this release: their lanes did not pass.\n\n- linux-arm64\n- wasi\n"

    assert_equal "Not in this release: their lanes did not pass.\n\n- linux-arm64\n- wasi", Release.left_out(body)
  end

  def test_left_out_is_nil_when_every_target_is_in
    assert_nil Release.left_out("Notes.\n\n- a list\n")
  end

  def test_left_out_is_nil_for_no_body
    assert_nil Release.left_out(nil)
  end

  def test_the_prerelease_tag_has_the_short_hash
    assert_equal "v0.1.0.gf7e13d2", Release.prerelease_tag("0.1.0", "f7e13d250aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  end

  def test_a_run_with_a_release_job_that_passed_is_passed
    runs = [ci_run(1, "push", "completed")]

    state, found = Release.ci_state(runs) { [{ "name" => JOB, "conclusion" => "success" }] }

    assert_equal [:passed, 1], [state, found["id"]]
  end

  def test_a_run_in_progress_with_a_passed_release_job_is_passed
    runs = [ci_run(1, "push", "in_progress")]

    state, = Release.ci_state(runs) { [{ "name" => JOB, "conclusion" => "success" }] }

    assert_equal :passed, state
  end

  def test_no_run_yet_is_waiting
    state, found = Release.ci_state([]) { flunk "no run has jobs" }

    assert_equal [:waiting, nil], [state, found]
  end

  def test_a_run_of_a_pull_request_does_not_count
    runs = [ci_run(1, "pull_request", "completed")]

    state, = Release.ci_state(runs) { flunk "a pull request's run has no say" }

    assert_equal :waiting, state
  end

  def test_a_run_in_progress_without_the_release_job_is_waiting
    runs = [ci_run(1, "push", "in_progress")]

    state, = Release.ci_state(runs) { [{ "name" => JOB, "conclusion" => nil }] }

    assert_equal :waiting, state
  end

  def test_runs_that_ended_with_no_release_job_passed_are_failed
    runs = [ci_run(1, "push", "completed"), ci_run(2, "schedule", "completed")]

    state, found = Release.ci_state(runs) { [{ "name" => JOB, "conclusion" => "failure" }] }

    assert_equal [:failed, 2], [state, found["id"]]
  end

  def test_one_run_in_progress_keeps_the_wait_open_after_another_failed
    runs = [ci_run(1, "push", "completed"), ci_run(2, "workflow_dispatch", "in_progress")]

    state, = Release.ci_state(runs) { [{ "name" => JOB, "conclusion" => "failure" }] }

    assert_equal :waiting, state
  end

  private

  def ci_run(id, event, status) = { "id" => id, "event" => event, "status" => status, "created_at" => "2026-11-02T10:0#{id}:00Z" }
end
