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

