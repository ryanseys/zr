# A RUN-TIME `define_method` on a shared class's singleton. The compiled
# half and this one land in different tables -- the frozen registry and the
# runtime overlay -- so both need saying.



b = Ruby::Box.new
b.eval("Array.singleton_class.define_method(:dyn) { 42 }")
p Array.respond_to?(:dyn)
p b.eval("Array.dyn")
