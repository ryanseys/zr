# Multi-argument `block.call(a, b, ...)` on the proc-object path.
#
# Each positional argument reaches its block param, not only the
# first one.

# 1. Basic: forwarded `&block` invoked with 2 args.
class T_multi_arg_block_call_App
  def run(&block)
    block.call(10, 20)
  end
end

T_multi_arg_block_call_App.new.run { |a, b| puts a + b }

# 2. 3-arg block.call.
class T_multi_arg_block_call_Wider
  def go(&block)
    block.call(1, 2, 3)
  end
end

T_multi_arg_block_call_Wider.new.go { |x, y, z| puts x + y + z }

# 3. Same proc invoked twice with different concrete args.
class T_multi_arg_block_call_Twice
  def both(&block)
    block.call(100, 1)
    block.call(200, 2)
  end
end

T_multi_arg_block_call_Twice.new.both { |a, b| puts a * b }

# 4. 0-param block called with one arg. Extra arg is silently dropped
# (matches CRuby semantics).
class T_multi_arg_block_call_Drop
  def go(&block)
    block.call(99)
  end
end

T_multi_arg_block_call_Drop.new.go { puts "called" }
