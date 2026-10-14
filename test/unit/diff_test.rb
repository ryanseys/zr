# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/diff"

# How `zr diff` and `zr-dev probe` compare a run under ruby with a run of
# the zr binary (lib/zr/diff.rb). The diff is zr's own, in Ruby: zr runs
# no `diff` program.
class DiffTest < Minitest::Test
  Answer = Zr::Diff::Answer

  def answer(stdout: "", stderr: "", status: 0, signal: nil, timeout: false) = Answer.new(stdout, stderr, status, signal, timeout)

  def test_each_kind_of_difference_has_its_name
    ruby = answer(stdout: "1\n")

    {
      "same" => answer(stdout: "1\n"),
      "output-diff" => answer(stdout: "2\n"),
      "exception-diff" => answer(stdout: "1\n", stderr: "boom\n"),
      "status-diff" => answer(stdout: "1\n", status: 1),
      "crash" => answer(signal: 11),
      "timeout" => answer(signal: 9, timeout: true)
    }.each { |kind, zr| assert_equal kind, Zr::Diff.kind(ruby, zr) }
  end

  # A program whose child outlives it keeps the pipes open: the run ends
  # at its limit with the whole process group, and does not wait for the
  # child.
  def test_a_run_ends_at_its_limit_when_a_child_keeps_the_pipes
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    answer = Zr::Diff.run([RbConfig.ruby, "-e", "fork { sleep 30 }; puts 1"], limit: 1)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, :<, 10
    assert answer.timeout
    assert_equal "1\n", answer.stdout
  end

  def test_same_texts_have_no_diff
    assert_equal "", Zr::Diff.unified("a\nb\n", "a\nb\n")
  end

  def test_a_changed_line_is_one_hunk_with_its_context
    a = "1\n2\n3\n4\n5\n6\n7\n8\n"
    b = "1\n2\n3\n4\nfive\n6\n7\n8\n"

    assert_equal "@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+five\n 6\n 7\n 8\n", Zr::Diff.unified(a, b)
  end

  def test_changes_far_apart_are_two_hunks
    a = (1..20).map { |i| "#{i}\n" }.join
    b = a.sub("2\n", "two\n").sub("19\n", "nineteen\n")

    assert_equal 2, Zr::Diff.unified(a, b).scan(/^@@/).size
  end

  def test_one_empty_side_starts_at_line_zero
    assert_equal "@@ -0,0 +1 @@\n+a\n", Zr::Diff.unified("", "a\n")
    assert_equal "@@ -1 +0,0 @@\n-a\n", Zr::Diff.unified("a\n", "")
  end

  def test_a_last_line_without_a_newline_is_marked
    assert_equal "@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n\\ No newline at end of file\n", Zr::Diff.unified("a", "b")
  end

  # Each script rebuilds both texts, and is as short as a script can be:
  # the number of changed lines is the size of the two texts less two
  # times their longest common subsequence.
  def test_the_edit_script_is_shortest_and_rebuilds_both_texts
    rng = Random.new(3)
    200.times do
      old = Array.new(rng.rand(0..12)) { %w[a b c][rng.rand(3)] }
      new = Array.new(rng.rand(0..12)) { %w[a b c][rng.rand(3)] }
      edits = Zr::Diff.script(old, new)

      assert_equal old, edits.filter_map { |op, i, _| old[i] if op != :ins }
      assert_equal new, edits.filter_map { |op, _, j| new[j] if op != :del }
      assert_equal old.size + new.size - (2 * lcs(old, new)), edits.count { |op, _, _| op != :same }
    end
  end

  def lcs(a, b)
    row = Array.new(b.size + 1, 0)
    a.each do |x|
      prev = 0
      b.each_with_index do |y, j|
        keep = row[j + 1]
        row[j + 1] = x == y ? prev + 1 : [row[j + 1], row[j]].max
        prev = keep
      end
    end
    row.last
  end

  def test_the_report_shows_each_part_that_differs
    report = Zr::Diff.report(answer(stdout: "1\n"), answer(stdout: "2\n", status: 1))

    assert_includes report, "--- stdout (ruby, then zr)\n"
    assert_includes report, "-1\n+2\n"
    assert_includes report, "--- status (ruby, then zr)\n"
    refute_includes report, "stderr"
  end

  def test_an_address_is_the_same_in_both
    assert_equal "#<Object:0x...>", Zr::Diff.unaddressed("#<Object:0x000000012345abcd>")
  end
end
