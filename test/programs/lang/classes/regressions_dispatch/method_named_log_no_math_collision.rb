# Method names that collide with Math module functions (log, sin,
# cos, sqrt, exp, atan2, hypot, ...) should not be misinferred as
# float-returning. A `def log; @log; end` accessor on a user class
# returns the ivar's Array, so `obj.log[i]` reads an element.

class T_method_named_log_no_math_collision_Notebook
  attr_accessor :log
  def initialize
    @log = []
  end
  def add(line)
    @log.push(line)
  end
end

n = T_method_named_log_no_math_collision_Notebook.new
n.add("first")
n.add("second")
entries = n.log
puts entries[0]
puts entries[1]
puts entries.length.to_s

# Also verify Math.log still works
puts Math.log(1.0).to_i.to_s
