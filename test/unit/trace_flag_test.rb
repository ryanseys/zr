# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# A program that reaches TracePoint only by a name it computes is built
# without trace events (lib/zr/hir/build/loader.rb, TRACE_NAMES). Its
# code fires none, and enabling a TracePoint warns once. `--trace` and
# `ZR_TRACE=1` arm the events, so its output is ruby's.
class TraceFlagTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  PROGRAM = <<~RUBY
    def double(x) = x * 2

    calls = []
    point = Object.const_get(%w[Trace Point].join).new(:call) { |tp| calls << tp.method_id }
    point.enable { double(1) }
    point.enable { double(2) }
    p calls
  RUBY

  def test_an_untraced_build_warns_once
    out, err = run_program

    assert_equal "[]\n", out
    assert_equal 1, err.scan("zr: warning: a TracePoint is enabled").size, err
  end

  def test_the_flag_arms_the_events
    out, err = run_program("--trace")

    assert_equal "[:double, :double]\n", out
    assert_empty err
  end

  def test_the_variable_arms_the_events
    out, err = run_program(env: { "ZR_TRACE" => "1" })

    assert_equal "[:double, :double]\n", out
    assert_empty err
  end

  private

  #: (*String flags, ?env: Hash[String, String]) -> [String, String]
  def run_program(*flags, env: {})
    Dir.mktmpdir("zr-trace-") do |dir|
      program = File.join(dir, "main.rb")
      File.write(program, PROGRAM)
      out, err, status = Open3.capture3(env, EXE, "run", *flags, program)
      assert_predicate status, :success?, err
      [out, err]
    end
  end
end
