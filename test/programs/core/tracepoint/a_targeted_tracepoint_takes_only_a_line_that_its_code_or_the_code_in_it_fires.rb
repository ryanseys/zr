# TracePoint#enable(target:, target_line:) hooks only a line where the
# target's code, or code in it (blocks, nested defs), fires a :line event,
# and refuses any other line, as rb_iseq_add_local_tracepoint_recursively.
def foo
  a = 1
  b = 2
  [a, b].each do |x|
    x
  end
  def inner = :inner
  inner
rescue
  :rescued
ensure
  a
end

def t(label)
  print label, ": "
  p yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

lines = []
tp = TracePoint.new(:line) { |t| lines << t.lineno }
[5, 6, 8, 10, 11, 15].each do |line|
  lines.clear
  t(:"line#{line}") { tp.enable(target: method(:foo), target_line: line) { foo }; lines.dup }
end
[4, 12, 13, 16, 40, -1].each do |line|
  t(:"line#{line}") { tp.enable(target: method(:foo), target_line: line) { foo } }
end
t(:no_target) { tp.enable(target_line: 5) { foo } }
t(:call_event) { TracePoint.new(:call) { }.enable(target: method(:foo), target_line: 5) { } }
t(:string_line) { tp.enable(target: method(:foo), target_line: "5") { foo } }

pr = proc { |z|
  z
}
lines.clear
t(:proc_body) { tp.enable(target: pr, target_line: 39) { pr.call(1) }; lines.dup }
t(:proc_open) { tp.enable(target: pr, target_line: 38) { pr.call(1) } }

class Target
  define_method(:made) do
    :made
  end
end
lines.clear
t(:define_method) { tp.enable(target: Target.instance_method(:made), target_line: 47) { Target.new.made }; lines.dup }
