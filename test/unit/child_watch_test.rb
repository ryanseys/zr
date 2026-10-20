# frozen_string_literal: true
# zr-test: on elf

require "test_helper"
require "rbconfig"
require_relative "../support/harness/child"

# `Harness::Child::Watch`: the resident size of a child's process group,
# which the memory limit of a run reads: from `ps` on macOS, from /proc
# on Linux, where BusyBox's `ps` (Alpine) gives no group.
class ChildWatchTest < Minitest::Test
  Watch = Zr::Harness::Child::Watch

  def setup
    @reader, writer = IO.pipe
    held = %(s = "x" * (64 << 20); s.setbyte(0, 1); $stdout.puts(:ready); $stdout.flush; sleep)
    @pid = Process.spawn(RbConfig.ruby, "-e", held, pgroup: true, out: writer)
    writer.close
    @reader.gets
  end

  def teardown
    Process.kill(:KILL, -@pid)
    Process.wait(@pid)
    @reader.close
  end

  # With no limits, a run only waits for its child.
  def test_a_run_with_no_limits_waits_for_the_child
    answer, = Zr::Harness::Child.run([RbConfig.ruby, "-e", "sleep 0.2; puts 1"], cwd: Dir.pwd, seconds: nil, megabytes: nil)

    assert_equal ["1\n", 0], [answer.stdout, answer.code]
  end

  def test_the_group_of_a_child_holds_what_it_allocated
    kb = Watch.read({ @pid => true }).fetch(@pid, 0)

    assert_operator kb, :>=, 32 << 10
  end

  def test_a_group_that_is_not_watched_is_not_read
    refute Watch.read({ @pid + 1_000_000 => true }).key?(@pid)
  end

  def test_proc_gives_the_group_on_linux
    skip "this host has no /proc" unless File.exist?("/proc/self/stat")

    assert_operator Watch.from_proc({ @pid => true }).fetch(@pid, 0), :>=, 32 << 10
  end
end
