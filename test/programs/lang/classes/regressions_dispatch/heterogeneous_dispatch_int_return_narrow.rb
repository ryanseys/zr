# `@slots[i][i]`, where `@slots` holds an Integer Array and a Method
# object. `[]` on each of them returns an Integer, so `@total += 1`
# does Integer math.

class T_heterogeneous_dispatch_int_return_narrow_Box
  def initialize
    @slots = [nil] * 4         # all nil at first
    @int_arr = [10, 20, 30, 40]
    @slots[0] = method(:double_at)   # a Method object
    @slots[1] = @int_arr             # an Integer Array
    @total = 0
  end

  def double_at(i)
    i * 2
  end

  # Direct ivar access.
  def via_ivar(i)
    @slots[i][i]
  end

  # Access through a local that aliases the ivar.
  def via_local(i)
    cache = @slots
    cache[i][i]
  end

  def run
    # IntArray arm of @slots[1]: returns @int_arr[1] = 20.
    @total = via_ivar(1)
    @total += 1
    puts @total                # 21
    # Method arm of @slots[0]: returns double_at(0) = 0.
    @total = via_local(0)
    @total += 1
    puts @total                # 1
  end
end

T_heterogeneous_dispatch_int_return_narrow_Box.new.run
