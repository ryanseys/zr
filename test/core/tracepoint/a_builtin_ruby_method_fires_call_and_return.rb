# A :call and a :return fire around the methods CRuby writes in Ruby of its
# own, at the place each one stands in CRuby's builtin sources; a method
# whose Ruby definition stands only under a JIT stays C's.
ev = []
tp = TracePoint.new(:call, :return) { |t| ev << [t.event, t.method_id, t.path, t.lineno, t.defined_class] }
tp.enable
[1].each {}
3.times {}
1.tap {}
[1].map {}
Integer("3")
[3, 1].sort
tp.disable
ev.each { |e| p e }

__END__
[:call, :times, "<internal:numeric>", 255, Integer]
[:return, :times, "<internal:numeric>", 266, Integer]
[:call, :tap, "<internal:kernel>", 89, Kernel]
[:return, :tap, "<internal:kernel>", 93, Kernel]
[:call, :Integer, "<internal:kernel>", 288, Kernel]
[:return, :Integer, "<internal:kernel>", 293, Kernel]
[:call, :disable, "<internal:trace_point>", 297, TracePoint]
