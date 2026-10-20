# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../lib/zr/timing"

# The progress line of a long build (lib/zr/notice.rb): on a terminal,
# each phase rewrites one line, and the end of the phase erases it.
class NoticeTest < Minitest::Test
  # A StringIO that says it is a terminal.
  class Terminal < StringIO
    def tty? = true
  end

  def teardown
    Zr::Session.current.forget(:notice)
    Zr::Session.current.forget(:notice_phases)
  end

  def on_a_terminal(env = {})
    was = $stderr
    $stderr = Terminal.new
    with_env({ "TERM" => "xterm", "ZR_TIMING" => nil, "ZR_QUIET" => nil }.merge(env)) do
      Zr::Notice.start
      yield
    end
    $stderr.string
  ensure
    $stderr = was
  end

  def test_each_phase_rewrites_the_line_and_its_end_erases_it
    err = on_a_terminal do
      Zr::Timing.phase("lowering the kernel", "kernel lowered") do
        Zr::Timing.phase("assembling", "assembled") { nil }
      end
    end

    assert_equal ["\r\e[Kzr: lowering the kernel (0 s)", "\r\e[Kzr: assembling (0 s)", "\r\e[Kzr: lowering the kernel (0 s)", "\r\e[K"],
                 err.scan(/\r\e\[K[^\r]*/)
  end

  def test_quiet_or_a_dumb_terminal_shows_no_line
    [{ "ZR_QUIET" => "1" }, { "TERM" => "dumb" }].each do |env|
      err = on_a_terminal(env) { Zr::Timing.phase("lowering", "lowered") { nil } }
      assert_equal "", err, env.inspect
    end
  end

  def test_no_start_shows_no_line
    was = $stderr
    $stderr = Terminal.new
    Zr::Timing.phase("lowering", "lowered") { nil }
    assert_equal "", $stderr.string
  ensure
    $stderr = was
  end
end
