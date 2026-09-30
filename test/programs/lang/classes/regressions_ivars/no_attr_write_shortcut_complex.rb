# `def x=(v); @x = v * 2; end` looks like an attr_writer at first glance
# (single InstanceVariableWriteNode body) but the assignment value is a
# computation, not a bare param reference. So `c.doubled = 5` runs the
# method body, and the `* 2` makes the ivar 10.

class T_no_attr_write_shortcut_complex_C
  def initialize
    @doubled = 0
  end

  def doubled=(v)
    @doubled = v * 2
  end

  def get_doubled
    @doubled
  end
end

c = T_no_attr_write_shortcut_complex_C.new

c.doubled = 5
puts c.get_doubled    # 10  (5 * 2)

c.doubled = -7
puts c.get_doubled    # -14

puts "done"
