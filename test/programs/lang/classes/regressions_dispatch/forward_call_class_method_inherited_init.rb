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


# Forward-ref `Class.new(arg)` whose Class is a subclass with its
# own `def initialize(_arg); super; end`. The bare `super` passes the
# argument to the parent's #initialize, so `@owner` holds the Outer
# object, and `@owner.name` calls Outer#name.

class T_forward_call_class_method_inherited_init_Outer
  def initialize
    @child = T_forward_call_class_method_inherited_init_Sub.new(self)
  end
  def report
    @child.read_owner_name
  end
  def name; "outer"; end
end

class T_forward_call_class_method_inherited_init_Base
  def initialize(owner)
    @owner = owner
  end
  def read_owner_name
    @owner.name
  end
end

class T_forward_call_class_method_inherited_init_Sub < T_forward_call_class_method_inherited_init_Base
  def initialize(_owner)
    super
  end
end

o = T_forward_call_class_method_inherited_init_Outer.new
puts o.report
