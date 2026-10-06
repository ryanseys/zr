# A Location keeps its path apart from its line. zr reads both from the
# row's text, where a frame at line 0 shows no line, so a path that ends
# in a colon and digits loses them.
begin
  eval("raise 'z'", nil, "a:12", 0)
rescue => e
  p e.backtrace.first, e.backtrace_locations.first.path, e.backtrace_locations.first.lineno
end
