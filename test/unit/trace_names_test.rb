# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# Tests whether a program needs `:line` events.
#
# A program that refers to `TracePoint`, `set_trace_func`,
# `add_trace_func` or `Coverage` is built again with an event before
# every statement. That has a large, hidden cost in code size and run
# time. Thus the check reads the parsed program, not its bytes: a
# comment that mentions TracePoint must not enable line events for
# every file of the program.
class TraceNamesTest < Minitest::Test
  def test_comment_that_mentions_tracing_does_not_enable_it
    refute traces?("# TracePoint would tell us, if we asked it\np 1\n")
    refute traces?("p 1 # set_trace_func\n")
    refute traces?("=begin\nCoverage\n=end\np 1\n")
  end

  def test_code_that_refers_to_tracing_enables_it
    ["TracePoint.new(:line) { }.enable", "::TracePoint", "set_trace_func(proc { })",
     "add_trace_func(proc { })", "send(:set_trace_func, proc { })", "Coverage.start"].each do |source|
      assert traces?("#{source}\n"), source
    end
  end

  # A name that zr cannot resolve also enables line events. Line events
  # in a program that does not trace cost time, but a missed program
  # that traces gives a wrong result.
  def test_a_name_reached_through_a_string_still_arms_it
    assert traces?(%(Object.const_get("TracePoint")\n))
  end

  private

  def traces?(source)
    loader = Zr::Hir::Build::Loader.new([])
    loader.unit("names.rb", source)
    loader.traces?
  end
end
