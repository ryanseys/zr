# A Location keeps its path apart from its line. A frame at line 0
# shows no line in its row, so a path that ends in a colon and digits
# keeps them.

def show(loc) = p([loc.to_s, loc.path, loc.lineno, loc.label])

begin
  eval("raise 'z'", nil, "a:12", 0)
rescue => e
  p e.backtrace.first
  show e.backtrace_locations.first
end

show eval("caller_locations(0).first", nil, "b:7", 0)
show eval("caller_locations(0).first", nil, "c:7", 3)
show eval("caller_locations(0).first", nil, "plain", 0)
show eval("caller_locations(0).first", nil, "d:x", 0)
locs = eval("[caller_locations(0, 1), caller_locations(0, 2), caller_locations(1, 1)]", nil, "e:5", 0)
locs.each { |ls| p ls.map { |l| [l.path, l.lineno] } }
show caller_locations(0).first
