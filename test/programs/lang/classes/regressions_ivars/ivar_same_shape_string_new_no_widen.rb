# Two `String.new` writes to the same ivar, in two methods. Each one
# gives a String that `<<` can append to.

class T_ivar_same_shape_string_new_no_widen_T
  def initialize
    @body = String.new
  end

  def reset
    @body = String.new
  end

  def append(s)
    @body << s
  end

  def body
    @body
  end
end

t = T_ivar_same_shape_string_new_no_widen_T.new
t.append("hello")
puts t.body
t.reset
t.append("world")
puts t.body
