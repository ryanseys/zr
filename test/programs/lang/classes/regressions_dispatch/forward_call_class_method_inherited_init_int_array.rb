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


# Inherited-init forward-ref with an Integer Array param that goes
# through the super call. The parent's `@arr = arr` stores the Array,
# and a parent-defined accessor reads it.

class T_forward_call_class_method_inherited_init_int_array_Driver
  def initialize
    @child = T_forward_call_class_method_inherited_init_int_array_Subscriber.new([10, 20, 30, 40])
  end
  def report
    @child.length
  end
end

class T_forward_call_class_method_inherited_init_int_array_Listener
  def initialize(arr)
    @arr = arr
  end
  def length
    @arr.length
  end
end

class T_forward_call_class_method_inherited_init_int_array_Subscriber < T_forward_call_class_method_inherited_init_int_array_Listener
  def initialize(_arr)
    super
  end
end

d = T_forward_call_class_method_inherited_init_int_array_Driver.new
puts d.report
