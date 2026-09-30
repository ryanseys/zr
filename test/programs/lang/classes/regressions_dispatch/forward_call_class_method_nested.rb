# Nested forward-ref: `T_forward_call_class_method_nested_Outer.new(T_forward_call_class_method_nested_Inner.new)` where both T_forward_call_class_method_nested_Outer and
# T_forward_call_class_method_nested_Inner are defined later than the construction site. The T_forward_call_class_method_nested_Inner.new
# nested arg must reach T_forward_call_class_method_nested_Outer.initialize's param as the Inner
# object.

class T_forward_call_class_method_nested_Driver
  def boot
    @outer = T_forward_call_class_method_nested_Outer.new(T_forward_call_class_method_nested_Inner.new(42))
  end
  def reach
    @outer.payload.value
  end
end

class T_forward_call_class_method_nested_Inner
  def initialize(v)
    @v = v
  end
  def value
    @v
  end
end

class T_forward_call_class_method_nested_Outer
  def initialize(inner)
    @inner = inner
  end
  def payload
    @inner
  end
end

d = T_forward_call_class_method_nested_Driver.new
d.boot
puts d.reach
