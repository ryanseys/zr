# ObjectSpace: weak maps the collector prunes, and finalizers that run
# after GC.start or at exit.
m = ObjectSpace::WeakMap.new
kept = Object.new
m[kept] = :kept
m[Object.new] = :gone
m[2] = :two
GC.start
p m[kept], m[2]
p m.inspect.gsub(/0x[0-9a-f]+/, "0xADDR")
p m.delete(kept), m.delete(:absent) { |k| [:missing, k] }
m2 = ObjectSpace::WeakMap.new
p m2.inspect.gsub(/0x[0-9a-f]+/, "0xADDR")

k = ObjectSpace::WeakKeyMap.new
name = "name"
k[name] = 1
GC.start
p k["name"], k.getkey("name").equal?(name), k.inspect.gsub(/0x[0-9a-f]+/, "0xADDR")
p k.delete("name"), k.inspect.gsub(/0x[0-9a-f]+/, "0xADDR")

def register
  o = Object.new
  ObjectSpace.define_finalizer(o, proc { |id| puts "finalized #{id.class}" })
  ObjectSpace.define_finalizer(o, proc { puts "second" })
  nil
end
register
GC.start
puts "after"

live = Object.new
ObjectSpace.define_finalizer(live) { puts "at exit" }
gone = Object.new
ObjectSpace.define_finalizer(gone, proc { puts "never" })
ObjectSpace.undefine_finalizer(gone)
begin
  ObjectSpace.define_finalizer(:sym, proc {})
rescue ArgumentError => e
  puts e.message
end
begin
  ObjectSpace.define_finalizer(Object.new.freeze, proc {})
rescue FrozenError => e
  puts e.class
end
p ObjectSpace.define_finalizer(Object.new, proc {}).first
p ObjectSpace.garbage_collect
puts "end"
