# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/ir"
require_relative "../../lib/ze0/backend/aarch64"

# The backend's work grows with the function, not with its square.
#
# Every constant is made in the entry block, so one read at the end of a
# long function is live across every block before it. Liveness kept as a
# set a block grew as blocks times values: a method of 3000 statements
# held more than 2.6 GB to compile. The shape here is that one at its
# smallest -- a chain of blocks, each comparing against a constant wide
# enough to need a register -- compiled at two sizes, and the processor
# time the compile takes is held to the ratio of the sizes, with room for
# a noisy machine: four times the blocks took sixteen times as long when
# the sets grew as their product. The objects allocated do not show it,
# as a Set's entries are not objects of their own.
class RegallocScaleTest < Minitest::Test
  def chain(n)
    f = Ze0::IR::Function.new("chain_#{n}", %w[i64], "i64")
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

  # The fastest of three compiles, so one pause for something else on
  # the machine does not decide it.
  def seconds(n)
    f = chain(n)
    Array.new(3) do
      GC.start
      started = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      Ze0::Backend::Aarch64::Codegen.new(f).compile
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - started
    end.min
  end

  def test_compile_time_grows_with_the_function
    small = seconds(500)
    large = seconds(2000)
    assert_operator large, :<, small * 8, "4x the blocks took #{(large / small).round(1)}x as long"
  end
end
