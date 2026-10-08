# The binding of a :call event of a core method that CRuby writes in Ruby
# (Kernel#class, in <internal:kernel>) is that method's own: no locals,
# and the method's receiver. zr runs such a method with no frame of its
# own, so the binding is made for the event (TracePoint#binding).

outer = 1
seen = []
TracePoint.new(:call) do |tp|
  next unless tp.method_id == :class

  bound = tp.binding
  seen << [tp.method_id, bound.local_variables, bound.receiver, bound.local_variable_defined?(:outer)]
end.enable do
  outer.class
  "text".class
end
p seen
