# Refinement has no include, prepend, append_features, prepend_features
# or extend_object; TracePoint.new converts event names with to_sym.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
show(1) { TracePoint.new(123) { } }
o = Object.new; def o.to_sym = 1
show(2) { TracePoint.new(o) { } }
s = Object.new; def s.to_sym = :line
show(3) { TracePoint.new(s) { }.class }
module M1
  refine(String) do
    show(4) { include(Comparable) }
    show(5) { prepend(Comparable) }
  end
end
r = nil
Module.new { refine(String) { r = self } }
show(6) { Object.new.extend(r) }
show(7) { Refinement.private_instance_methods(false).sort }
show(8) { Refinement.private_method_defined?(:append_features) }
