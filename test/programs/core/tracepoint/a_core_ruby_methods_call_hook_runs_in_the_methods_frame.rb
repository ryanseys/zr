# The hooks of :call and :return of a core method that CRuby writes in
# Ruby (Kernel#class, in <internal:kernel>) run in the method's own
# frame, so caller_locations and a debugger (rb_debug_inspector_open)
# see it, shown with its caller's file. A C method's :c_call hook sees
# no frame of it.

outer = 1
seen = []
TracePoint.new(:call, :return, :c_call) do |tp|
  next unless %i[class upcase].include?(tp.method_id)

  seen << [tp.event, caller_locations(1, 2).map { |l| [File.basename(l.path), l.label] }]
end.enable do
  outer.class
  "a".upcase
end
p seen
