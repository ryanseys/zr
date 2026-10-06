require "objspace"
def t(name)
  p [name, yield]
rescue Exception => e
  p [name, e.class, e.message]
end
t(:roots) { r = ObjectSpace.reachable_objects_from_root; [r.class, r.keys.all?(String)] }
t(:internal_super) { ObjectSpace.internal_super_of(String).class }
