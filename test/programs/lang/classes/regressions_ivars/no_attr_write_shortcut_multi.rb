# `obj.x = v` must dispatch to `def x=(v)` when x= is not a registered
# attr_writer. The multi-statement body runs, with its side effect on
# another ivar.

class T_no_attr_write_shortcut_multi_C
  attr_accessor :real

  def initialize
    @real = 0
    @logged = ""
  end

  # Multi-statement writer. Side-effects on a *different* ivar so we can
  # tell whether the def actually ran.
  def logged=(v)
    @logged = "set:" + v
    @real = v.length
  end

  def get_logged
    @logged
  end
end

c = T_no_attr_write_shortcut_multi_C.new

# attr_accessor path: writes the ivar.
c.real = 7
puts c.real           # 7

# Multi-statement def x=: the method body runs.
c.logged = "hello"
puts c.get_logged     # set:hello
puts c.real           # 5  (overwritten by the side effect)

puts "done"
