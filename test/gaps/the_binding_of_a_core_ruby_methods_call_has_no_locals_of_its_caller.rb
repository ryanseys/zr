# The binding of a :call event of a core method that CRuby writes in Ruby
# (Kernel#class, in <internal:kernel>) is that method's own, with no
# locals. zr runs such a method as a builtin with no frame of its own, so
# TracePoint#binding gives nil, and a C hook that sends local_variables
# to that nil gets the locals of its caller.

outer = 1
seen = []
TracePoint.new(:call) { |tp| seen << [tp.method_id, tp.binding&.local_variables] if tp.method_id == :class }.enable do
  outer.class
end
p seen
