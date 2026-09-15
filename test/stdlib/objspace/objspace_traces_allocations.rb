# ObjectSpace.trace_object_allocations records where each object was made:
# the file and line of the Ruby code, and the C method it was made in, if
# any. An object made while tracing is off has no record.
require "objspace"

class Foo
  def make = "x" * 2
end

ObjectSpace.trace_object_allocations do
  $made = Object.new
  $joined = Foo.new.make
  $mapped = [1, 2].map { |v| v.to_s }
end
[$made, $joined, $mapped, $mapped[0]].each do |obj|
  p [ObjectSpace.allocation_sourcefile(obj), ObjectSpace.allocation_sourceline(obj),
     ObjectSpace.allocation_class_path(obj), ObjectSpace.allocation_method_id(obj),
     ObjectSpace.allocation_generation(obj).class]
end
p ObjectSpace.allocation_sourcefile(Object.new)
p ObjectSpace.trace_object_allocations_start, ObjectSpace.trace_object_allocations_stop
p ObjectSpace.trace_object_allocations_clear
p ObjectSpace.allocation_sourcefile($made)

# The census and the sizes.
p ObjectSpace.memsize_of_all.class, ObjectSpace.memsize_of_all(String).positive?
sizes = ObjectSpace.count_objects_size
p sizes.keys.first(3), sizes.keys.last, sizes[:TOTAL] >= sizes[:T_STRING]
p ObjectSpace.count_symbols.keys
p ObjectSpace.count_tdata_objects.class, ObjectSpace.count_imemo_objects.class
p ObjectSpace.internal_class_of("a")

# dump writes JSON; the address and the sizes are the runtime's own.
p ObjectSpace.dump("abc")[/"type":"STRING"/], ObjectSpace.dump("abc")[/"value":"abc"/]
p ObjectSpace.dump(nil), ObjectSpace.dump(7), ObjectSpace.dump(true)

__END__
["stdlib/objspace/objspace_traces_allocations.rb", 11, nil, nil, Integer]
["stdlib/objspace/objspace_traces_allocations.rb", 7, "String", :*, Integer]
["stdlib/objspace/objspace_traces_allocations.rb", 13, "Array", :map, Integer]
["stdlib/objspace/objspace_traces_allocations.rb", 13, "Integer", :to_s, Integer]
nil
nil
nil
nil
nil
Integer
true
[:T_OBJECT, :T_CLASS, :T_MODULE]
:TOTAL
true
[:mortal_dynamic_symbol, :immortal_dynamic_symbol, :immortal_static_symbol, :immortal_symbol]
Hash
Hash
String
"\"type\":\"STRING\""
"\"value\":\"abc\""
"null"
"7"
"true"
