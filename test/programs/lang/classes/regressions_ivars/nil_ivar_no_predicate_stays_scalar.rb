# The optcarrot APU::Pulse shape: an ivar initialized to `nil` and
# later used only in Integer arithmetic (no `.nil?` read anywhere on
# it). `@freq = (@wave_length + 1) * 2 * @fixed` and the later
# arithmetic on `@timer` and `@step` give the right Integers.

class T_nil_ivar_no_predicate_stays_scalar_APUFake
  def initialize
    @wave_length = nil
    @fixed = 1
    @freq = 0
    @timer = 0
    @step = 0
  end

  def configure(n)
    @wave_length = n
    @freq = (@wave_length + 1) * 2 * @fixed
    @timer = @freq
  end

  def step!
    @step = (@step + 1) & 7
    @timer += @freq
    @step
  end

  def report
    @step.to_s + "," + @timer.to_s
  end
end

a = T_nil_ivar_no_predicate_stays_scalar_APUFake.new
a.configure(3)
puts a.report
a.step!
a.step!
puts a.report
