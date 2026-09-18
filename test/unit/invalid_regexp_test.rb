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

  # ruby's compiler writes nothing for an expression whose value nothing
  # takes, so it never reads a regexp written there: the pattern that is
  # a SyntaxError as a scope's value is a program that runs one line up.
  # Each program below was asked of ruby 4.0.6, and each one runs.
  def test_a_pattern_nothing_takes_the_value_of_is_never_read
    [
      "puts 1\n/[z-a]/\nputs 2\n",                   # before the last statement
      "def m\n  /[z-a]/\n  1\nend\n",                # of a method's body
      "[1].each { /[z-a]/; 1 }\n",                   # of a block's
      "class K\n  /[z-a]/\n  1\nend\n",              # of a class body's
      "while false do /[z-a]/ end\n",                # a loop answers nil
      "true && /[z-a]/\nputs 1\n",                   # the right of a pair
      "if true then /[z-a]/ end\nputs 1\n",          # a branch, where the if is
      "puts 1\n(/[z-a]/)\nputs 2\n",                 # inside parentheses
      "puts 1\nbegin\n  /[z-a]/\nend\nputs 2\n",     # a protected region's body
      "puts 1\nbegin\n 2\nrescue\n 3\nelse\n /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase 1\nwhen 1 then /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase 9\nwhen 1 then 2\nelse /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase [1]\nin [x] then /[z-a]/\nend\nputs 2\n",
      "begin\n 2\nensure\n /[z-a]/\nend\n"           # an ensure answers nothing
    ].each { |source| build(source) }
  end

  # Where ruby does read one, though the shape looks alike: a `rescue`
  # body answers for the region, and a `for` body is a block's, whose
  # last expression is the block's value.
  def test_a_pattern_ruby_still_reads_is_still_refused
    assert_raises(Hir::Invalid) { build("puts 1\nbegin\n raise 1\nrescue\n /[z-a]/\nend\nputs 2\n") }
    assert_raises(Hir::Invalid) { build("for i in [1] do /[z-a]/ end\nputs 1\n") }
    assert_raises(Hir::Invalid) { build("p(case 1\nwhen 1 then /[z-a]/\nend)\n") }
  end

  # A condition written as a literal chooses its branch as the program is
  # built, and ruby writes nothing for the branch it never chooses. One
  # the program decides is not that, and both branches are read.
  def test_a_branch_a_literal_condition_never_chooses_is_never_read
    ["if false then /[z-a]/ end\n", "if nil then /[z-a]/ end\n", "unless true then /[z-a]/ end\n",
     "if true then 1 else /[z-a]/ end\n"].each { |source| build(source) }

    assert_raises(Hir::Invalid) { build("if 1 == 2 then /[z-a]/ end\n") }
    assert_raises(Hir::Invalid) { build("unless false then /[z-a]/ end\n") }
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
