# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/ir"
require_relative "../../lib/zr/backend/aarch64"

# The backend's work grows with the size of the function, not with its
# square.
#
# Every constant is made in the entry block, so one read at the end of a
# long function is live across every block before it. When each block
# keeps liveness as a set, memory grows as blocks times values: then a
# method of 3000 statements used more than 2.6 GB to compile. This test
# uses the smallest form of that shape: a chain of blocks, each compared
# against a constant wide enough to need a register. It compiles the
# chain at two sizes and checks that the processor time follows the
# ratio of the sizes, with a margin for a noisy machine. With sets per
# block, four times the blocks took sixteen times as long. The count of
# allocated objects does not show the problem, because the entries of a
# Set are not separate objects.
class RegallocScaleTest < Minitest::Test
  def chain(n)
    f = Zr::IR::Function.new("chain_#{n}", %w[i64], "i64")
    a = f.args.first
    n.times do |i|
      found = f.label
      onward = f.label
      f.brif(f.icmp("eq", a, f.iconst("i64", (i << 20) | 0x12345)), found, onward)
      f.switch(found)
      f.ret(f.iconst("i64", i))
      f.switch(onward)
    end
    f.ret(a)
    f
  end

  # The fastest of three compiles, so that one pause for other work on
  # the machine does not decide the result. The collector stays off in
  # the timed part: a major collection there depends on what the worker
  # ran before, not on the compile.
  def seconds(n)
    f = chain(n)
    Array.new(3) do
      GC.start
      GC.disable
      started = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      Zr::Backend::Aarch64::Codegen.new(f).compile
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - started
    ensure
      GC.enable
    end.min
  end

  def test_compile_time_grows_with_the_function
    small = seconds(500)
    large = seconds(2000)
    assert_operator large, :<, small * 8, "4x the blocks took #{(large / small).round(1)}x as long"
  end
end
