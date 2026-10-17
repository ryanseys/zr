# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# A program that turns off CRuby's specialized instructions
# (`RubyVM::InstructionSequence.compile_option`) sends `new` as a call of
# Class#new, which a TracePoint hears. The loader reads the assignment
# from the source, as rb_iseq_compile_option_set reads its value. The
# program test core/tracepoint/a_file_compiled_after_compile_option_* checks
# the events end to end.
class PlainNewDetectionTest < Minitest::Test
  def test_a_hash_that_turns_the_option_off_sends_new
    assert plain_new?("RubyVM::InstructionSequence.compile_option = { specialized_instruction: false }")
    assert plain_new?("RubyVM::InstructionSequence.compile_option = { specialized_instruction: nil, debug_level: 1 }")
    assert plain_new?("::RubyVM::InstructionSequence.compile_option = { specialized_instruction: false }")
  end

  # true gives the options of `--dump` debugging, false turns all off:
  # both turn off the specialized instructions.
  def test_true_and_false_turn_the_option_off
    assert plain_new?("RubyVM::InstructionSequence.compile_option = true")
    assert plain_new?("RubyVM::InstructionSequence.compile_option = false")
  end

  def test_a_value_that_keeps_the_option_keeps_the_inline_new
    refute plain_new?("RubyVM::InstructionSequence.compile_option = nil")
    refute plain_new?("RubyVM::InstructionSequence.compile_option = { specialized_instruction: true }")
    refute plain_new?("RubyVM::InstructionSequence.compile_option = { debug_level: 2 }")
    refute plain_new?("p RubyVM::InstructionSequence.compile_option[:specialized_instruction]")
    refute plain_new?("Other.compile_option = false")
  end

  # The build cannot tell what a value made at run time holds.
  def test_a_value_that_the_build_cannot_read_counts
    assert plain_new?("options = {}\nRubyVM::InstructionSequence.compile_option = options")
    assert plain_new?("off = false\nRubyVM::InstructionSequence.compile_option = { specialized_instruction: off }")
    assert plain_new?("RubyVM::InstructionSequence.compile_option = { **{} }")
  end

  private

  # `program: false` leaves out eval support: only the loader's scan runs.
  def plain_new?(source) = Zr::Hir.build("#{source}\n", "plain_new_test.rb", program: false).plain_new
end
