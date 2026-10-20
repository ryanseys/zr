# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/native/resident"

# `Native::Resident`: the resident size of a process, from the system
# (proc_pidinfo on macOS, /proc on Linux), with no `ps` child, which a
# BusyBox `ps` (Alpine) cannot answer by pid.
class ResidentTest < Minitest::Test
  Resident = Zr::Native::Resident

  def test_this_process_holds_some_megabytes
    bytes = Resident.bytes_of(Process.pid)
    skip "this system gives no resident size" unless bytes

    assert_operator bytes, :>, 1 << 20
    # A second reading, a moment later, may differ by a little.
    assert_in_delta bytes / (1 << 20), Resident.of(Process.pid), 4
  end

  def test_a_process_that_is_gone_has_no_size
    pid = Process.spawn(RbConfig.ruby, "-e", "")
    Process.wait(pid)

    assert_nil Resident.bytes_of(pid)
  end
end
