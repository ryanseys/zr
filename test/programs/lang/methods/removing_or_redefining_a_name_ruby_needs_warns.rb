# Removing object_id, __id__, __send__ or initialize, and redefining
# object_id, __id__ or __send__ warn even when $VERBOSE is false.
$VERBOSE = false
%i[object_id __id__ __send__ initialize].each do |name|
  Class.new.instance_eval { remove_method(name) }
rescue NameError
  p name
end
def (Object.new).object_id; end
def (Object.new).__id__; end
Class.new.attr_reader(:__send__)
$VERBOSE = nil
def (Object.new).__id__; end
