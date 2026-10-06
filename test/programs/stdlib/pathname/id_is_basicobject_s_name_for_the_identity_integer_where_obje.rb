# Which CLASS owns a builtin method is part of its behaviour, not a detail of
# reflection: it decides which receivers answer it. This locks the boundaries
# the arity census proved zr had drawn in the wrong place.

require "pathname"
require "tmpdir"

def owner_of(klass, name)
  klass.instance_method(name).owner
rescue NameError
  "absent"
end

# `__id__` is the root's name for the identity integer; `object_id` is Kernel's.
puts "-- BasicObject, not Kernel"
o = Object.new
p owner_of(Object, :__id__)
p owner_of(Object, :object_id)
p o.__id__ == o.object_id

