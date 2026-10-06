p TracePoint.stat.keys.map(&:class)
p TracePoint.stat.values
point = TracePoint.new(:call) {}
point.enable
p TracePoint.stat.values
point.disable
p TracePoint.stat.values
