# A method made from a Symbol's Proc has that Proc's parameters, and no
# source location.
c = Class.new { define_method(:klass, :class.to_proc) }
m = c.instance_method(:klass)
p m.parameters, m.source_location, :class.to_proc.parameters
