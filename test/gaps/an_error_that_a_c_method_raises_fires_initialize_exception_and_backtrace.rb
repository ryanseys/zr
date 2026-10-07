# An error that a C method raises for the program (rb_raise) is made with
# rb_class_new_instance and raised with rb_exc_raise, so a :c_call
# TracePoint sees `initialize`, then `exception` and `backtrace`. zr
# writes these methods in Ruby, whose raise fires `exception` and then
# `initialize` (Exception.exception calls new), or fires nothing for a
# raise in the kernel, as for ZeroDivisionError.
seen = []
TracePoint.new(:c_call) { |tp| seen << tp.method_id if tp.path == __FILE__ }.enable do
  1 / 0 rescue nil
  [].fetch(3) rescue nil
end
p seen
