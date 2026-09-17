#@ skip: power_assert's re-parse hits `Prism::CallNode#location=`, which the port does not define
# A test-unit suite runs under the console runner: a pass, a failure with
# its diff, an error, and a power_assert block that shows each value.
require "test/unit"
require "stringio"
require "test/unit/ui/console/testrunner"

Test::Unit::AutoRunner.need_auto_run = false

class ArithmeticTest < Test::Unit::TestCase
  def test_sum = assert_equal(4, 2 + 2)
  def test_failure = assert_equal([1, 2], [1, 3])
  def test_error = Integer("four")
  def test_raise = assert_raise(ZeroDivisionError) { 1 / 0 }

  def test_power_assert
    numbers = [1, 2, 3]
    assert { numbers.sum == 7 }
  end
end

out = StringIO.new
runner = Test::Unit::UI::Console::TestRunner.new(ArithmeticTest.suite, output: out, use_color: false)
result = runner.start
puts out.string.lines.reject { |line| line.match?(/Finished in|tests\/s|^Loaded suite|^\s+\d+: |^  => /) }
puts result.summary
p result.passed?






__END__
Started
E
===============================================================================
Error: test_error(ArithmeticTest): ArgumentError: invalid value for Integer(): "four"
e2e/stdlib/testing/a_test_unit_suite_runs.rb:13:in 'Kernel#Integer'
e2e/stdlib/testing/a_test_unit_suite_runs.rb:13:in 'ArithmeticTest#test_error'
===============================================================================
F
===============================================================================
Failure: test_failure(ArithmeticTest)
e2e/stdlib/testing/a_test_unit_suite_runs.rb:12:in 'ArithmeticTest#test_failure'
<[1, 2]> expected but was
<[1, 3]>

diff:
? [1, 2]
?     3 
?     ? 
===============================================================================
F
===============================================================================
Failure: test_power_assert(ArithmeticTest):
      assert { numbers.sum == 7 }
               |       |   |
               |       |   false
               |       6
               [1, 2, 3]
e2e/stdlib/testing/a_test_unit_suite_runs.rb:18:in 'ArithmeticTest#test_power_assert'
===============================================================================
-------------------------------------------------------------------------------
5 tests, 4 assertions, 2 failures, 1 errors, 0 pendings, 0 omissions, 0 notifications
40% passed
-------------------------------------------------------------------------------
5 tests, 4 assertions, 2 failures, 1 errors, 0 pendings, 0 omissions, 0 notifications
false
