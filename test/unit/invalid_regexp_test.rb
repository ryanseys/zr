# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/hir"
require "stringio"

# A pattern the engine will not compile.
#
# ruby reads a regexp literal as it compiles the string around it, so
# such a pattern is a syntax error and not a run-time one. ze0 asks the
# host's engine the same question, and answers with
# `Hir::Hir::Invalid`: a build reports it as a refusal and names the
# line, and a program that compiles the pattern while it runs sees the
# SyntaxError ruby raises there.
#
# ruby 4.0.6 is the oracle for every message below.
class InvalidRegexpTest < Minitest::Test
  Hir = Ze0::Hir

  def test_a_pattern_the_engine_refuses_is_named_at_its_line
    error = assert_raises(Hir::Invalid) { build("p 1\np(/[z-a]/)\n") }

    assert_equal "pattern.rb:2: empty range in char class: /[z-a]/", error.message
  end

  def test_a_repeat_range_that_counts_backwards_reads_as_ruby_reads_it
    error = assert_raises(Hir::Invalid) { build("p(/a{2,1}/)\n") }

    assert_equal "pattern.rb:1: upper is smaller than lower in repeat range: /a{2,1}/", error.message
  end

  # It is still a refusal, so the build road keeps the exit and the line
  # it has always had.
  def test_it_is_a_refusal_as_well
    assert_operator Hir::Invalid, :<, Hir::Refused
  end

  # ruby warns about a pattern from an eval too, on the program's own
  # stderr, whether or not `-w` is given. A compile the eval road makes
  # runs inside the program, so it lets the engine warn there rather than
  # taking $stderr and $VERBOSE from every thread the program has.
  def test_a_warning_from_a_run_time_compile_goes_where_ruby_sends_it
    program = nil
    said = capturing_stderr { program = build("x = /(?:a?)*b/\n") }

    assert_includes said, "nested repeat operator"
    assert_empty program.warnings
  end

  private

  # The HIR of `source`, built as the eval road builds one: no road
  # carried, and the loader in the mode a run-time compile uses.
  def build(source) = Ze0::Hir.build(source, "pattern.rb", road: false)

  def capturing_stderr
    said = StringIO.new
    stderr, $stderr = $stderr, said
    yield
    said.string
  ensure
    $stderr = stderr
  end
end
