# Nested blocks that capture a variable through string interpolation
# inside a block that itself captures the same variable.
#
# LocalVariableReadNode("i") is nested under
#   InterpolatedStringNode → EmbeddedStatementsNode → body
# and each block sees the last value of `i`.

class T_nested_proc_interp_capture_Defer
  def initialize
    @cnt = 0
  end

  def add(&blk)
    if @cnt == 0
      @blk0 = blk
    elsif @cnt == 1
      @blk1 = blk
    else
      @blk2 = blk
    end
    @cnt += 1
    nil
  end

  def call
    @blk2.call
    @blk1.call
    @blk0.call
  end
end

class T_nested_proc_interp_capture_Runner
  def self.with_deferred(&outer)
    d = T_nested_proc_interp_capture_Defer.new
    outer.call(d)
    d.call
  end
end

T_nested_proc_interp_capture_Runner.with_deferred do |d|
  i = 1
  d.add { puts "first #{i}" }
  i += 1
  d.add { puts "second #{i}" }
  puts "mid"
  i += 1
  d.add { puts "third #{i}" }
end
