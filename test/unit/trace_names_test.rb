# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/hir"

# Whether a program needs `:line` events.
#
# A program that names `TracePoint`, `set_trace_func`, `add_trace_func`
# or `Coverage` is built again with an event before every statement,
# which is a large, silent cost in both the code written and the time
# taken. So the question has to be asked of what the program says, not
# of the bytes it is written in: prose that mentions TracePoint must not
# arm line events for every file of the program.
class TraceNamesTest < Minitest::Test
  def test_prose_that_names_tracing_does_not_arm_it
    refute traces?("# TracePoint would tell us, if we asked it\np 1\n")
    refute traces?("p 1 # set_trace_func\n")
    refute traces?("=begin\nCoverage\n=end\np 1\n")
  end

  def test_a_program_that_names_tracing_arms_it
    ["TracePoint.new(:line) { }.enable", "::TracePoint", "set_trace_func(proc { })",
     "add_trace_func(proc { })", "send(:set_trace_func, proc { })", "Coverage.start"].each do |source|
      assert traces?("#{source}\n"), source
    end
  end

  # A name ze0 cannot read through still arms it: the cost of arming a
  # program that does not trace is time, and the cost of missing one is
  # a wrong answer.
  def test_a_name_reached_through_a_string_still_arms_it
    assert traces?(%(Object.const_get("TracePoint")\n))
  end

  private

  def traces?(source)
    loader = Ze0::Hir::Build::Loader.new([])
    loader.unit("names.rb", source)
    loader.traces?
  end
end
