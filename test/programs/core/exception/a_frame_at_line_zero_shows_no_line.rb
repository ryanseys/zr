# location_format writes a frame at line 0 without its line, and a
# Location of such a row has line 0.
begin
  eval("raise 'x'", nil, "f.rb", 0)
rescue => e
  p e.backtrace.first
  location = e.backtrace_locations.first
  p [location.path, location.lineno, location.label, location.to_s]
end
begin
  eval("\nraise 'y'", nil, "g.rb", 0)
rescue => e
  p e.backtrace.first, e.backtrace_locations.first.lineno
end
p eval("__LINE__", nil, "h.rb", 0)
p eval("[__LINE__, caller_locations(0, 1).first.lineno]", nil, "h.rb", 0)
