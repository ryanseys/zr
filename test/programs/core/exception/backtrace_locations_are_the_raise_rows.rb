# The rows the raise saw, as Location objects: nil before a raise, and
# unchanged when set_backtrace replaces the strings.
def inner = raise("x")
def outer = inner

begin
  outer
rescue => e
  l = e.backtrace_locations
  p l.class, l.size, l.map(&:class).uniq
  f = l.first
  p f.lineno, f.label, f.base_label, f.path, f.to_s, f.inspect
  p f.absolute_path == File.expand_path(__FILE__)
  p l.map(&:to_s) == e.backtrace
end

p RuntimeError.new("y").backtrace_locations
e = RuntimeError.new("z")
e.set_backtrace(["a.rb:1:in 'm'"])
p e.backtrace_locations, e.backtrace

begin
  raise "w"
rescue => e2
  e2.set_backtrace(["b.rb:2"])
  p e2.backtrace_locations.size, e2.backtrace
end

