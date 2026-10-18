# rb_hash calls an object's Kernel#hash directly (rb_check_funcall_basic_kw)
# but through rb_vm_call0, so a TracePoint still hears the c_call.
o = Object.new
seen = []
tp = TracePoint.new(:c_call) { |x| seen << x.method_id if x.method_id == :hash }
tp.enable
h = { o => 1 }
h[o]
[o].hash
tp.disable
p seen
P = Struct.new(:a)
p P.new(o).hash == P.new(o).hash, { P.new(o) => 1 }[P.new(o)]
