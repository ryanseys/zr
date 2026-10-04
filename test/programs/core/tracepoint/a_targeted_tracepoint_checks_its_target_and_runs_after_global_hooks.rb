# TracePoint#enable(target:) refuses an event or a line that the target
# cannot fire, refuses nesting, and its hook runs after the global ones.
def r = yield
t = TracePoint.new(:call) {}
b = proc {}
p((t.enable(target: b) { b.call } rescue $!.message))
t = TracePoint.new(:b_call) {}
p((t.enable(target: -> {}) { t.enable {} } rescue $!.message))
p((t.enable(target: -> {}) { t.disable {} } rescue $!.message))
rec = []
o = TracePoint.new(:b_call) { rec << :outer }
i = TracePoint.new(:b_call) { rec << :inner }
target = -> {}
o.enable { i.enable(target: target) { target.call } }
p rec
t = TracePoint.new(:line) {}
p((t.enable(target_line: 1, target: -> { }) {} rescue $!.message))
p((t.enable(target_line: Object.new, target: -> { }) {} rescue [$!.class, $!.message]))
p((t.enable(target_line: -2, target: -> { }) {} rescue $!.message))
lines = []
t = TracePoint.new(:line) { |tp| lines << tp.lineno }
tg = -> {
  x = 1
}
t.enable(target_line: (__LINE__ - 2).to_r, target: tg) { tg.call }
p lines
