# Process.warmup leaves each object that it keeps in the old generation,
# as rb_gc_prepare_heap promotes every survivor. An object made after it
# is young, and a minor collection keeps it through an old Array.
require "objspace"
GC.disable
def age(o) = ObjectSpace.dump(o)[/"age":\d/]
a = Object.new
b = [a, +"text"]
h = { b => a }
p [age(a), age(b), age(h)]
Process.warmup
p [age(a), age(b), age(b[1]), age(h)]
c = Object.new
b << c
p age(c)
GC.start(full_mark: false)
p b[2].equal?(c)
p age(c)
