# ObjectSpace.allocation_method_id is the method that runs when the object
# is made: the C method, or else the method of the Ruby frame, and none
# at the top level. Its class path is nil for an anonymous or a singleton
# class.
require "objspace"
def made_here = Object.new
class K; def mk = "a" * 3; def self.smk = [1]; end
o = ObjectSpace.trace_object_allocations { made_here }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { K.new.mk }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { K.smk }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { Object.new }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { +"x" }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { [1].map { |x| x.to_s } }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
m = Module.new { def self.mk = Object.new }
o = ObjectSpace.trace_object_allocations { m.mk }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
module Named; def self.mk = Object.new; def inst = [] ; end
o = ObjectSpace.trace_object_allocations { Named.mk }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
o = ObjectSpace.trace_object_allocations { Object.new.extend(Named).inst }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
def in_block = [1].each { return Object.new }
o = ObjectSpace.trace_object_allocations { in_block }
p [ObjectSpace.allocation_method_id(o), ObjectSpace.allocation_class_path(o)]
