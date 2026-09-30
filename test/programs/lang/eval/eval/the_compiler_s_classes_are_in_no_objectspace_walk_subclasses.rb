# The compiler's classes are in no ObjectSpace walk, no subclasses list
# and no hook of the program.
added = []
Object.define_singleton_method(:inherited) { |k| added << k.name; super(k) }
Module.define_method(:method_added) { |m| added << m if Integer == self }
before = ObjectSpace.each_object(Class).count
subclasses = Object.subclasses.size
eval("class Mine; end")
p ObjectSpace.each_object(Class).count - before, Object.subclasses.size - subclasses, added
