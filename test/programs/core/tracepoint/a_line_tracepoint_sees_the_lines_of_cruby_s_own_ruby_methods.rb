# CRuby writes some core methods in Ruby (<internal:kernel> and the
# others), and a :line TracePoint sees the lines of their bodies, after
# their :call.
def internal_lines
  lines = []
  TracePoint.new(:line) do |tp|
    lines << "#{tp.path}:#{tp.lineno} #{tp.method_id}" if tp.path.start_with?("<internal:")
  end.enable { yield }
  lines
end

# A body with no block guard.
p internal_lines { GC.start }
p internal_lines { 1.frozen? }
p internal_lines { nil.to_i }
p internal_lines { 1.5.to_f }

# A guard on the block: a call without one leaves at the guard.
p internal_lines { 1.then }
p internal_lines { 1.then { :x } }
p internal_lines { 1.then(&:itself) }
p internal_lines { 3.times }
p internal_lines { loop }

# A body split on Primitive.mandatory_only?: a call of only the
# mandatory arguments runs the first half.
p internal_lines { [1, 2].first }
p internal_lines { [1, 2].last }
p internal_lines { Float("1.5") }
p internal_lines { Float("x", exception: false) }

# The :line events come after the :call, and before the block's own.
events = []
TracePoint.new(:call, :return, :line) do |tp|
  events << [tp.event, tp.lineno, tp.method_id] if tp.method_id == :then || tp.path == __FILE__
end.enable do
  1.then do
    :inside
  end
end
p events

# An enabled point hears the line of the TracePoint#enable that turns
# on a second one.
code = proc { _x = 1 }
heard = []
outer = TracePoint.new(:line) { |tp| heard << [:outer, tp.path.start_with?("<internal:") ? tp.lineno : :program] }
inner = TracePoint.new(:line) { |tp| heard << [:inner, tp.lineno] }
outer.enable do
  inner.enable(target: code) { code.call }
end
p heard.uniq

# A targeted point does not see the lines of a core method that its
# target calls.
seen = []
target = proc { 1.then { 2 } }
TracePoint.new(:line) { |tp| seen << tp.path }.enable(target: target) { target.call }
p seen.uniq.map { |path| File.basename(path) }
