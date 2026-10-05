# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/cruby_test"

# The program that runs a test file under CRuby's runner, and the reader
# of its report. A test that calls `omit` is a skip, not a pass: the
# runner lists it only with --show-skip, so a test that ruby omits does
# not count as one that zr fails.
class CRubyTestRunnerTest < Minitest::Test
  def test_the_program_asks_the_runner_to_list_skips
    program = Zr::Dev::CRubyTest.program("/ruby", ["/ruby/test/ruby/test_x.rb"])

    assert_includes program, %(ARGV.replace(["-v", "--tty=no", "--show-skip", *ARGV]))
  end

  def test_a_skipped_test_reads_as_a_skip
    out = +<<~OUT
      [1/2] TestAst#test_of_proc = 0.00 s
      [2/2] TestAst#test_allocate = 0.00 s

        1) Skipped:
      TestAst#test_of_proc [test/ruby/test_ast.rb:419]:
      Skipped, no message given

      Finished tests in 0.003465s, 288.6003 tests/s, 0.0000 assertions/s.
    OUT

    examples = Zr::Dev::CRubyTest.read(out)[:examples]

    assert_equal "skip", examples.fetch("TestAst#test_of_proc").first
    assert_equal ["pass"], examples.fetch("TestAst#test_allocate")
  end
end
