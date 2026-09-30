
# The landing block is shared: `Fx::new` creates ONE of it and every
# `Fx::fallible` branches there, so a raise anywhere in a method reaches the
# same epilogue that a normal return does -- and that epilogue releases every
# slot in `fx.locals` unconditionally.
#
# A fused `n.times` loop takes no run-time guard. Here a raise comes BEFORE
# the loop, so the method reaches the landing without ever running the
# block. The block parameter's slot must hold a value that is safe to
# release at that point. This pins the path.
#
# Runs under `ZR_TEST_RT_LEAKCHECK=1`; the printed output is the same either way.
#
# LIMIT: a bad release on this path does not always show. What this example
# adds is coverage of the path, so a LOUD failure on it is caught.

def raises_before_a_loop(obj)
  obj.no_such_method
  3.times { |i| p i }
rescue NoMethodError => e
  e.class
end

def raises_before_a_range_loop(obj)
  obj.no_such_method
  (0...3).each { |i| p i }
rescue NoMethodError => e
  e.class
end

p raises_before_a_loop(Object.new)
p raises_before_a_range_loop(Object.new)
