# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"
require "stringio"

# Tests a pattern that the regexp engine does not compile.
#
# ruby reads a regexp literal when it compiles the code around it, so an
# invalid pattern is a syntax error, not a run-time error. zr checks the
# pattern with the host's engine and raises `Hir::Invalid`. A build
# reports it as a refusal with the line. A program that compiles the
# pattern while it runs gets the SyntaxError that ruby raises.
#
# Each message is the one that the host ruby gives for the same pattern.
class InvalidRegexpTest < Minitest::Test
  Hir = Zr::Hir

  def test_invalid_pattern_error_gives_its_line
    error = assert_raises(Hir::Invalid) { build("p 1\np(/[z-a]/)\n") }

    assert_equal "pattern.rb:2: #{ruby_message("[z-a]")}", error.message
  end

  def test_backwards_repeat_range_gives_ruby_message
    error = assert_raises(Hir::Invalid) { build("p(/a{2,1}/)\n") }

    assert_equal "pattern.rb:1: #{ruby_message("a{2,1}")}", error.message
  end

  # `Hir::Invalid` is a refusal, so a build gives the refusal exit status
  # and the line.
  def test_it_is_a_refusal_as_well
    assert_operator Hir::Invalid, :<, Hir::Refused
  end

  # ruby also warns about a pattern in an eval, on the program's stderr,
  # with or without `-w`. Eval support compiles inside the program, so
  # it lets the engine write the warning there. It does not take
  # $stderr and $VERBOSE from all threads of the program.
  def test_run_time_compile_warning_goes_to_stderr
    program = nil
    said = capturing_stderr { program = build("p(/(?:a?)*b/)\n") }

    assert_includes said, "nested repeat operator"
    assert_empty program.warnings
  end

  # ruby's compiler writes no code for an expression whose value is not
  # used, so it never reads a regexp there. The same pattern is a
  # SyntaxError when it is the value of a scope. Each program below was
  # checked against ruby, and each one runs.
  def test_a_pattern_nothing_takes_the_value_of_is_never_read
    [
      "puts 1\n/[z-a]/\nputs 2\n",                   # before the last statement
      "def m\n  /[z-a]/\n  1\nend\n",                # of a method's body
      "[1].each { /[z-a]/; 1 }\n",                   # of a block's
      "class K\n  /[z-a]/\n  1\nend\n",              # of a class body's
      "while false do /[z-a]/ end\n",                # a loop returns nil
      "true && /[z-a]/\nputs 1\n",                   # the right of a pair
      "if true then /[z-a]/ end\nputs 1\n",          # a branch, where the if is
      "puts 1\n(/[z-a]/)\nputs 2\n",                 # inside parentheses
      "puts 1\nbegin\n  /[z-a]/\nend\nputs 2\n",     # a protected region's body
      "puts 1\nbegin\n 2\nrescue\n 3\nelse\n /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase 1\nwhen 1 then /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase 9\nwhen 1 then 2\nelse /[z-a]/\nend\nputs 2\n",
      "puts 1\ncase [1]\nin [x] then /[z-a]/\nend\nputs 2\n",
      "begin\n 2\nensure\n /[z-a]/\nend\n"           # an ensure returns no value
    ].each { |source| build(source) }
  end

  # ruby reads the pattern in these cases, although they look similar.
  # A `rescue` body gives the value of the region. A `for` body is a
  # block, and its last expression is the value of the block.
  def test_a_pattern_ruby_still_reads_is_still_refused
    assert_raises(Hir::Invalid) { build("puts 1\nbegin\n raise 1\nrescue\n /[z-a]/\nend\nputs 2\n") }
    assert_raises(Hir::Invalid) { build("for i in [1] do /[z-a]/ end\nputs 1\n") }
    assert_raises(Hir::Invalid) { build("p(case 1\nwhen 1 then /[z-a]/\nend)\n") }
  end

  # A literal condition selects its branch at build time, and ruby writes
  # no code for the other branch. If the program computes the condition,
  # ruby reads both branches.
  def test_pattern_in_unchosen_literal_branch_is_not_read
    ["if false then /[z-a]/ end\n", "if nil then /[z-a]/ end\n", "unless true then /[z-a]/ end\n",
     "if true then 1 else /[z-a]/ end\n"].each { |source| build(source) }

    assert_raises(Hir::Invalid) { build("if 1 == 2 then /[z-a]/ end\n") }
    assert_raises(Hir::Invalid) { build("unless false then /[z-a]/ end\n") }
  end

  private

  # Returns the HIR of `source`, built as eval support builds it: with no
  # eval support linked in, and the loader in the run-time compile mode.
  def build(source) = Zr::Hir.build(source, "pattern.rb", program: false)

  # The message of the RegexpError that ruby raises for `pattern`.
  def ruby_message(pattern)
    Regexp.new(pattern)
    flunk "ruby compiles /#{pattern}/"
  rescue RegexpError => e
    e.message
  end

  def capturing_stderr
    said = StringIO.new
    stderr, $stderr = $stderr, said
    yield
    said.string
  ensure
    $stderr = stderr
  end
end
