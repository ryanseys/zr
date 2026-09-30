# instance_eval as an expression: the block's last expression is the
# call's value (CRuby semantics). An assignment-only block gives the
# assigned value, so `if obj.instance_eval { @f = 1 }` is truthy.

class T_instance_eval_return_value_Counter
  def initialize
    @count = 0
  end
  def inc
    @count = @count + 1
  end
end

c = T_instance_eval_return_value_Counter.new
c.inc
c.inc
c.inc

# Int-valued block returns the ivar, not the receiver.
n = c.instance_eval { @count }
puts n   # 3

# Boolean-valued block.
big = c.instance_eval { @count > 2 }
puts big # true

# Arithmetic expression body.
doubled = c.instance_eval { @count + @count }
puts doubled # 6

# String-valued block.
class T_instance_eval_return_value_Greeter
  def initialize
    @greeting = "hello"
  end
end

g = T_instance_eval_return_value_Greeter.new
msg = g.instance_eval { @greeting }
puts msg # hello

# Assignment body: the value 1 is truthy, so the `if` arm runs.
class T_instance_eval_return_value_Flag
  def initialize
    @flag = 0
  end
end

f = T_instance_eval_return_value_Flag.new
if f.instance_eval { @flag = 1 }
  puts "truthy"
end

puts "done"
