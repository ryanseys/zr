# Inherited-init forward-ref where the param is an object of a
# user class. Verifies the object goes through both the
# `Class.new(@h)` constructor branch and the bare `super` of the
# child's initialize.

class T_forward_call_class_method_inherited_init_obj_Holder
  def initialize(name)
    @name = name
  end
  def label
    "h:#{@name}"
  end
end

class T_forward_call_class_method_inherited_init_obj_Outer
  def initialize
    @h = T_forward_call_class_method_inherited_init_obj_Holder.new("alpha")
    @child = T_forward_call_class_method_inherited_init_obj_Sub.new(@h)
  end
  def report
    @child.held_label
  end
end

class T_forward_call_class_method_inherited_init_obj_Base
  def initialize(holder)
    @holder = holder
  end
  def held_label
    @holder.label
  end
end

class T_forward_call_class_method_inherited_init_obj_Sub < T_forward_call_class_method_inherited_init_obj_Base
  def initialize(_holder)
    super
  end
end

o = T_forward_call_class_method_inherited_init_obj_Outer.new
puts o.report
