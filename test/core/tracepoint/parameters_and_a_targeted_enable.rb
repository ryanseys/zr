# TracePoint#parameters answers the parameters of the code an event is
# for, and enable(target:) sees only the events of the target's code and
# of the blocks written inside it, never a C event.
def foo(a, b = 1, *r, k:, &blk) = [1].each { |x, y| x }

seen = []
tp = TracePoint.new(:call, :b_call, :c_call, :return) { |t| seen << [t.event, t.method_id, t.parameters] }
tp.enable { foo(1, k: 2) }
seen.each { |row| p row }

def bar = [1].map { |v| v + 1 }
def baz = bar

seen.clear
targeted = TracePoint.new(:call, :line, :b_call, :return, :c_call) { |t| seen << [t.event, t.lineno, t.method_id] }
targeted.enable(target: method(:bar)) { baz; bar }
seen.each { |row| p row }
p targeted.enabled?

def lines
  a = 1
  b = 2
  a + b
end
seen.clear
TracePoint.new(:line) { |t| seen << t.lineno }.enable(target: method(:lines), target_line: 22) { lines }
p seen

p((TracePoint.new(:line) {}.enable(target_line: 3) rescue $!))
p((TracePoint.new(:line) {}.enable(target: 1) rescue $!))
p((TracePoint.new(:call) {}.enable(target: method(:puts)) rescue $!))
p((TracePoint.new(:call) {}.enable(target: method(:bar), target_line: 3) rescue $!))
p((TracePoint.new(:c_call) {}.enable(target: method(:bar)) rescue $!))

__END__
[:b_call, nil, []]
[:call, :foo, [[:req, :a], [:opt, :b], [:rest, :r], [:keyreq, :k], [:block, :blk]]]
[:c_call, :each, []]
[:b_call, :foo, [[:opt, :x], [:opt, :y]]]
[:return, :foo, [[:req, :a], [:opt, :b], [:rest, :r], [:keyreq, :k], [:block, :blk]]]
[:call, 11, :bar]
[:b_call, 11, :bar]
[:line, 11, :bar]
[:return, 11, :bar]
[:call, 11, :bar]
[:b_call, 11, :bar]
[:line, 11, :bar]
[:return, 11, :bar]
false
[22]
#<ArgumentError: only target_line is specified>
#<ArgumentError: specified target is not supported>
#<ArgumentError: specified target is not supported>
#<ArgumentError: target_line is specified, but line event is not specified>
false
