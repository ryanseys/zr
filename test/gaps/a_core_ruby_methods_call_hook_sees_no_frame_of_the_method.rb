# In the :call hook of a core method that CRuby writes in Ruby
# (Kernel#class, in <internal:kernel>), the method's own frame is on the
# stack, so caller_locations and a debugger (rb_debug_inspector_open)
# see it, shown with its caller's file. zr runs such a method with no
# frame of its own, so neither sees it.

outer = 1
seen = []
TracePoint.new(:call) do |tp|
  seen << caller_locations(1, 2).map { |l| [l.path.start_with?("<internal:") ? "<internal>" : File.basename(l.path), l.label] } if tp.method_id == :class
end.enable do
  outer.class
end
p seen
