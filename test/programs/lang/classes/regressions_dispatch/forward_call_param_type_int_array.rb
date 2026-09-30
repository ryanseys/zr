# File-order caller-first / callee-second: a T_forward_call_param_type_int_array_Caller class invokes a
# method on a yet-untyped ivar (because the callee class is defined
# later in the source). The callee's params get the Integer Array and
# the boolean from this single call site.

class T_forward_call_param_type_int_array_Caller
  def initialize(target)
    @target = target
    @arr = [1, 2, 3]
    @flag = false
  end
  def go
    @target.set_payload(@arr, @flag)
  end
end

class T_forward_call_param_type_int_array_Target
  def set_payload(arr, flag)
    @arr = arr
    @flag = flag
  end
  def info
    "len=#{@arr.length} flag=#{@flag}"
  end
end

t = T_forward_call_param_type_int_array_Target.new
c = T_forward_call_param_type_int_array_Caller.new(t)
c.go
puts t.info
