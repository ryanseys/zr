# rb_iseq_add_local_tracepoint: a target line that the code lacks takes
# only the :line events off, so a point that hears other events still
# enables. A :line hook fires only on the target line.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

def m1 = 1

def m2
  :two
end
seen = []
t("all events") { tp = TracePoint.new { |x| seen << x.event }; r = tp.enable(target: method(:m1), target_line: 3); m1; tp.disable; [r, seen] }
t("block form") { tp = TracePoint.new {}; tp.enable(target: method(:m1), target_line: 3) { 1r } }
t("line only") { tp = TracePoint.new(:line) {}; tp.enable(target: method(:m1), target_line: 3) }
t("call and line") { tp = TracePoint.new(:call, :line) {}; r = tp.enable(target: method(:m1), target_line: 99); tp.disable; r }
