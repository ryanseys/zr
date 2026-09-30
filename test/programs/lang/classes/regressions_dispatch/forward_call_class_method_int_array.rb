# `Class.new(an_integer_array)` where the callee class is defined later
# than the call site. The Target's `arr` param gets the Array. The
# source order keeps the caller first.

class T_forward_call_class_method_int_array_Caller
  def make_target
    @t = T_forward_call_class_method_int_array_Target.new([10, 20, 30])
  end
  def length
    @t.show
  end
end

class T_forward_call_class_method_int_array_Target
  def initialize(arr)
    @arr = arr
  end
  def show
    @arr.length
  end
end

c = T_forward_call_class_method_int_array_Caller.new
c.make_target
puts c.length
