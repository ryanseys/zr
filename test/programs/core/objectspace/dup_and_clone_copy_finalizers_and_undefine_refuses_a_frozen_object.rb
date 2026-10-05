# A dup or a clone gets the finalizers of the original, so each copy runs
# them at exit. undefine_finalizer refuses a frozen object.
pr = proc {}
ObjectSpace.define_finalizer(pr, proc { STDOUT.write "proc finalized\n" })
pr.dup
pr.clone
m = 1.method(:+)
ObjectSpace.define_finalizer(m, proc { STDOUT.write "method finalized\n" })
m.clone
o = Object.new
ObjectSpace.define_finalizer(o, proc { STDOUT.write "object finalized\n" })
o.dup
f = Object.new.freeze
p((ObjectSpace.undefine_finalizer(f) rescue $!.class))
kept = Object.new
ObjectSpace.define_finalizer(kept, proc { STDOUT.write "kept finalized\n" })
kept.freeze
p((ObjectSpace.undefine_finalizer(kept) rescue $!.class))
