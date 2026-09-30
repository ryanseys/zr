# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# An Outer and its inherited Sub hold each other through the forwarded class-method init.
# At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
# Bundled tests:
#   - fiber_ivar_persists_across_yield
#   - fiber_yield_across_method_call
#   - file_write_poly_arg
#   - forward_call_class_method_inherited_init
#   - forward_call_class_method_inherited_init_int_array


class T_fiber_ivar_persists_across_yield_Counter
  def initialize
    @n = 0
    @fiber = Fiber.new do
      @n += 10
      Fiber.yield
      @n += 100
      Fiber.yield
      @n += 1000
    end
  end

  def step
    @fiber.resume
    @n
  end
end

c = T_fiber_ivar_persists_across_yield_Counter.new
puts c.step
puts c.step
puts c.step
