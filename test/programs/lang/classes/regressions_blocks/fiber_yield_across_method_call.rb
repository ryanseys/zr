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


class T_fiber_yield_across_method_call_Stepper
  def initialize
    @count = 0
    @fiber = Fiber.new { main_loop }
  end

  def step
    @fiber.resume
    @count
  end

  def main_loop
    while @count < 5
      tick
      tick
      Fiber.yield
    end
  end

  def tick
    @count += 1
  end
end

s = T_fiber_yield_across_method_call_Stepper.new
puts s.step
puts s.step
puts s.step
