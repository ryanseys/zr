# While the hooks of :call, :b_call and :class run, the event's lineno is
# the scope's own line, but the frame (as caller_locations and a debugger
# see it) is on the first statement of the body. A body with no
# statement leaves the frame on the scope's line. A default argument does
# not count as the body.

def with_default(a,
                 b = a + 1)
  x = b
  x
end

def empty; end

def one_line(n) = n * 2

def after_blank

  :late
end

seen = []
point = TracePoint.new(:call, :b_call, :class) do |tp|
  next unless tp.path == __FILE__

  seen << [tp.event, tp.lineno, caller_locations(1, 1)[0].lineno]
end
point.enable
with_default(1)
empty
one_line(3)
after_blank
[1].each do |i|

  i
end
[2].each { |i| i }
class Opened

  X = 1
end
module Plain
  def self.y = 2
end
point.disable
seen.each { |row| p row }
